package tailnet

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type DropListener interface {
	OnProgress(job string, done int64, total int64, route string)
	OnDone(job string, sha256 string)
	OnError(job string, message string, retryable bool)
}

const (
	dropPart     = 16 << 20
	dropInFlight = 4
	dropFiles    = 2
	dropBuffer   = 256 << 10
	dropIdle     = 30 * time.Second
	dropEmit     = 250 * time.Millisecond
)

var (
	dropStall   = 60 * time.Second
	dropBackoff = 250 * time.Millisecond
	dropMaxWait = 5 * time.Second
)

type dropEndpoint struct {
	URL   string  `json:"url"`
	Pin   *string `json:"pin"`
	Tsnet bool    `json:"tsnet"`
}

type dropConfig struct {
	Endpoints []dropEndpoint `json:"endpoints"`
	Ticket    string         `json:"ticket"`
	DropID    string         `json:"dropId"`
	FileID    string         `json:"fileId"`
	Size      int64          `json:"size"`
}

var (
	dropMu    sync.Mutex
	dropJobs  = map[string]context.CancelFunc{}
	dropSlots = make(chan struct{}, dropFiles)
	errPin    = errors.New("the Mac's certificate did not match")
)

type statusError struct{ code int }

func (e *statusError) Error() string {
	switch e.code {
	case http.StatusUnauthorized:
		return "The transfer pass expired"
	case http.StatusForbidden:
		return "This device is not allowed to transfer files"
	case http.StatusNotFound:
		return "The Mac no longer has this transfer"
	case http.StatusConflict:
		return "The Mac is not ready for this file"
	case http.StatusRequestedRangeNotSatisfiable:
		return "The Mac refused part of the file"
	case http.StatusLocked:
		return "Paused"
	case http.StatusInsufficientStorage:
		return "Not enough space on the Mac"
	}
	return fmt.Sprintf("The Mac answered %d", e.code)
}

func (e *statusError) final() bool {
	switch e.code {
	case http.StatusUnauthorized, http.StatusForbidden, http.StatusNotFound, http.StatusConflict, http.StatusRequestedRangeNotSatisfiable, http.StatusInsufficientStorage:
		return true
	}
	return false
}

type transfer struct {
	ctx      context.Context
	job      string
	cfg      dropConfig
	file     *os.File
	listener DropListener
	clients  []*http.Client
	skip     []bool
	current  int
	route    atomic.Value
	done     atomic.Int64
	moved    atomic.Int64
	emitted  atomic.Int64
}

func DropUpload(job string, configJSON string, fd int, listener DropListener) error {
	return startDrop(job, configJSON, fd, listener, (*transfer).upload)
}

func DropDownload(job string, configJSON string, fd int, listener DropListener) error {
	return startDrop(job, configJSON, fd, listener, (*transfer).download)
}

func DropCancel(job string) {
	dropMu.Lock()
	cancel := dropJobs[job]
	dropMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func startDrop(job, configJSON string, fd int, listener DropListener, run func(*transfer) (string, error)) error {
	file := os.NewFile(uintptr(fd), job)
	if file == nil {
		return errors.New("bad file descriptor")
	}
	var cfg dropConfig
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		file.Close()
		return err
	}
	if len(cfg.Endpoints) == 0 || cfg.Size < 0 || cfg.Ticket == "" {
		file.Close()
		return errors.New("bad transfer job")
	}
	ctx, cancel := context.WithCancel(context.Background())
	dropMu.Lock()
	if _, busy := dropJobs[job]; busy {
		dropMu.Unlock()
		cancel()
		file.Close()
		return errors.New("already running")
	}
	dropJobs[job] = cancel
	dropMu.Unlock()
	t := &transfer{ctx: ctx, job: job, cfg: cfg, file: file, listener: listener, clients: make([]*http.Client, len(cfg.Endpoints)), skip: make([]bool, len(cfg.Endpoints))}
	t.route.Store(routeOf(cfg.Endpoints[0]))
	go func() {
		sum, err := t.queued(run)
		cancelled := ctx.Err() != nil
		cancel()
		for _, c := range t.clients {
			if c != nil {
				c.CloseIdleConnections()
			}
		}
		file.Close()
		dropMu.Lock()
		delete(dropJobs, job)
		dropMu.Unlock()
		var status *statusError
		switch {
		case err == nil:
			listener.OnDone(job, sum)
		case cancelled:
			listener.OnError(job, "Cancelled", false)
		case errors.Is(err, errPin):
			listener.OnError(job, "The Mac's certificate did not match", false)
		case errors.As(err, &status):
			listener.OnError(job, status.Error(), !status.final())
		default:
			listener.OnError(job, "Can't reach your Mac", true)
		}
	}()
	return nil
}

func (t *transfer) queued(run func(*transfer) (string, error)) (string, error) {
	select {
	case dropSlots <- struct{}{}:
	case <-t.ctx.Done():
		return "", t.ctx.Err()
	}
	defer func() { <-dropSlots }()
	t.moved.Store(time.Now().UnixNano())
	return run(t)
}

func routeOf(e dropEndpoint) string {
	if e.Pin != nil {
		return "lan"
	}
	return "tailnet"
}

func (t *transfer) url() string {
	e := t.cfg.Endpoints[t.current]
	return strings.TrimRight(e.URL, "/") + "/api/drop/" + url.PathEscape(t.cfg.DropID) + "/" + url.PathEscape(t.cfg.FileID)
}

func (t *transfer) client() *http.Client {
	if t.clients[t.current] == nil {
		t.clients[t.current] = dropClient(t.cfg.Endpoints[t.current])
	}
	return t.clients[t.current]
}

func (t *transfer) request(ctx context.Context, method string, body io.Reader) *http.Request {
	req, _ := http.NewRequestWithContext(ctx, method, t.url(), body)
	req.Header.Set("Authorization", "Drop "+t.cfg.Ticket)
	return req
}

func (t *transfer) add(n int64) {
	t.set(t.done.Add(n))
}

func (t *transfer) set(done int64) {
	t.done.Store(done)
	now := time.Now().UnixNano()
	t.moved.Store(now)
	last := t.emitted.Load()
	if now-last < int64(dropEmit) || !t.emitted.CompareAndSwap(last, now) {
		return
	}
	t.listener.OnProgress(t.job, done, t.cfg.Size, t.route.Load().(string))
}

func (t *transfer) retry(step func() error) error {
	failures := 0
	for {
		for t.skip[t.current] {
			t.next()
		}
		t.route.Store(routeOf(t.cfg.Endpoints[t.current]))
		t.client()
		err := step()
		if err == nil {
			return nil
		}
		if t.ctx.Err() != nil {
			return t.ctx.Err()
		}
		var status *statusError
		if errors.As(err, &status) && status.final() {
			return err
		}
		if errors.Is(err, errPin) {
			t.skip[t.current] = true
			if t.allSkipped() {
				return errPin
			}
		}
		if status == nil {
			t.next()
		}
		if time.Since(time.Unix(0, t.moved.Load())) > dropStall {
			return err
		}
		failures++
		wait := min(dropBackoff<<min(failures-1, 8), dropMaxWait)
		select {
		case <-time.After(wait):
		case <-t.ctx.Done():
			return t.ctx.Err()
		}
	}
}

func (t *transfer) next() {
	t.current = (t.current + 1) % len(t.cfg.Endpoints)
}

func (t *transfer) allSkipped() bool {
	for _, s := range t.skip {
		if !s {
			return false
		}
	}
	return true
}

func check(resp *http.Response, ok ...int) error {
	for _, code := range ok {
		if resp.StatusCode == code {
			return nil
		}
	}
	return &statusError{resp.StatusCode}
}

func (t *transfer) upload() (string, error) {
	hashed := make(chan string, 1)
	go func() {
		h := sha256.New()
		buf := make([]byte, dropBuffer)
		if _, err := io.CopyBuffer(h, &ctxReader{t.ctx, io.NewSectionReader(t.file, 0, t.cfg.Size)}, buf); err != nil {
			hashed <- ""
			return
		}
		hashed <- hex.EncodeToString(h.Sum(nil))
	}()
	err := t.retry(t.uploadRound)
	if err != nil {
		return "", err
	}
	sum := <-hashed
	if sum == "" {
		return "", errors.New("could not read the file")
	}
	return sum, nil
}

func (t *transfer) uploadRound() error {
	size := t.cfg.Size
	if size == 0 {
		req := t.request(t.ctx, http.MethodPut, http.NoBody)
		req.Header.Set("Content-Range", "bytes */0")
		return t.send(req, http.StatusNoContent)
	}
	have, err := t.head()
	if err != nil {
		return err
	}
	parts := int((size + dropPart - 1) / dropPart)
	var missing []int
	var received int64
	for i := range parts {
		if have[i] {
			received += partLen(i, size)
		} else {
			missing = append(missing, i)
		}
	}
	t.set(received)
	ctx, cancel := context.WithCancel(t.ctx)
	defer cancel()
	queue := make(chan int, len(missing))
	for _, i := range missing {
		queue <- i
	}
	close(queue)
	var wg sync.WaitGroup
	var first error
	var once sync.Once
	for range min(dropInFlight, len(missing)) {
		wg.Go(func() {
			for i := range queue {
				if err := t.putPart(ctx, i); err != nil {
					once.Do(func() { first = err; cancel() })
					return
				}
			}
		})
	}
	wg.Wait()
	return first
}

func partLen(i int, size int64) int64 {
	return min(dropPart, size-int64(i)*dropPart)
}

func (t *transfer) head() (map[int]bool, error) {
	resp, err := t.client().Do(t.request(t.ctx, http.MethodHead, nil))
	if err != nil {
		return nil, err
	}
	resp.Body.Close()
	if err := check(resp, http.StatusOK); err != nil {
		return nil, err
	}
	have := map[int]bool{}
	for _, s := range strings.Split(resp.Header.Get("X-Vitals-Parts"), ",") {
		if i, err := strconv.Atoi(strings.TrimSpace(s)); err == nil {
			have[i] = true
		}
	}
	return have, nil
}

func (t *transfer) putPart(ctx context.Context, i int) error {
	start := int64(i) * dropPart
	n := partLen(i, t.cfg.Size)
	req := t.request(ctx, http.MethodPut, &progressReader{t: t, r: io.NewSectionReader(t.file, start, n)})
	req.ContentLength = n
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, start+n-1, t.cfg.Size))
	return t.send(req, http.StatusNoContent)
}

func (t *transfer) send(req *http.Request, ok int) error {
	resp, err := t.client().Do(req)
	if err != nil {
		return err
	}
	io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	resp.Body.Close()
	return check(resp, ok)
}

func (t *transfer) download() (string, error) {
	size := t.cfg.Size
	h := sha256.New()
	buf := make([]byte, dropBuffer)
	st, err := t.file.Stat()
	if err != nil {
		return "", err
	}
	off := min(st.Size(), size)
	if st.Size() > size {
		if err := t.file.Truncate(size); err != nil {
			return "", err
		}
	}
	if off > 0 {
		if _, err := io.CopyBuffer(h, &ctxReader{t.ctx, io.NewSectionReader(t.file, 0, off)}, buf); err != nil {
			return "", err
		}
		t.set(off)
	}
	err = t.retry(func() error {
		if off == size && size > 0 {
			return nil
		}
		req := t.request(t.ctx, http.MethodGet, nil)
		if off > 0 {
			req.Header.Set("Range", fmt.Sprintf("bytes=%d-", off))
		}
		resp, err := t.client().Do(req)
		if err != nil {
			return err
		}
		defer resp.Body.Close()
		if err := check(resp, http.StatusOK, http.StatusPartialContent); err != nil {
			return err
		}
		if resp.StatusCode == http.StatusOK && off > 0 {
			h.Reset()
			off = 0
			t.set(0)
		}
		if resp.StatusCode == http.StatusPartialContent && !strings.HasPrefix(resp.Header.Get("Content-Range"), fmt.Sprintf("bytes %d-", off)) {
			return &statusError{http.StatusRequestedRangeNotSatisfiable}
		}
		for off < size {
			n, err := resp.Body.Read(buf[:min(int64(len(buf)), size-off)])
			if n > 0 {
				if _, werr := t.file.WriteAt(buf[:n], off); werr != nil {
					return werr
				}
				h.Write(buf[:n])
				off += int64(n)
				t.set(off)
			}
			if err != nil {
				if err == io.EOF && off == size {
					break
				}
				if err == io.EOF {
					return io.ErrUnexpectedEOF
				}
				return err
			}
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	if err := t.file.Truncate(size); err != nil {
		return "", err
	}
	if err := t.file.Sync(); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

type progressReader struct {
	t *transfer
	r io.Reader
}

func (p *progressReader) Read(b []byte) (int, error) {
	if err := p.t.ctx.Err(); err != nil {
		return 0, err
	}
	n, err := p.r.Read(b)
	if n > 0 {
		p.t.add(int64(n))
	}
	return n, err
}

type ctxReader struct {
	ctx context.Context
	r   io.Reader
}

func (c *ctxReader) Read(b []byte) (int, error) {
	if err := c.ctx.Err(); err != nil {
		return 0, err
	}
	return c.r.Read(b)
}

type idleConn struct{ net.Conn }

func (c *idleConn) Read(b []byte) (int, error) {
	c.SetDeadline(time.Now().Add(dropIdle))
	return c.Conn.Read(b)
}

func (c *idleConn) Write(b []byte) (int, error) {
	c.SetDeadline(time.Now().Add(dropIdle))
	return c.Conn.Write(b)
}

func pinned(pin string) func(tls.ConnectionState) error {
	return func(cs tls.ConnectionState) error {
		if len(cs.PeerCertificates) == 0 {
			return errPin
		}
		sum := sha256.Sum256(cs.PeerCertificates[0].RawSubjectPublicKeyInfo)
		if base64.StdEncoding.EncodeToString(sum[:]) != pin {
			return errPin
		}
		return nil
	}
}

func dropClient(e dropEndpoint) *http.Client {
	config := &tls.Config{MinVersion: tls.VersionTLS12}
	if e.Pin != nil {
		config.InsecureSkipVerify = true
		config.VerifyConnection = pinned(*e.Pin)
	}
	dialer := &net.Dialer{Timeout: 10 * time.Second, KeepAlive: 15 * time.Second}
	dial := dialer.DialContext
	if e.Tsnet {
		mu.Lock()
		s := server
		mu.Unlock()
		if s != nil {
			dial = s.Dial
		}
	}
	return &http.Client{Transport: &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			c, err := dial(ctx, network, addr)
			if err != nil {
				return nil, err
			}
			return &idleConn{c}, nil
		},
		TLSClientConfig:       config,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 60 * time.Second,
		IdleConnTimeout:       20 * time.Second,
		MaxIdleConnsPerHost:   dropInFlight,
		WriteBufferSize:       dropBuffer,
		ReadBufferSize:        dropBuffer,
	}}
}
