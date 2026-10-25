package tailnet

import (
	"bytes"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

const testTicket = "ticket-0123456789abcdef0123456789abcdef"

type fakeMac struct {
	mu      sync.Mutex
	data    []byte
	parts   map[int]bool
	puts    []int
	ranges  []string
	locked  int
	status  int
	cut     int64
	slow    bool
	request int
}

func (m *fakeMac) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	m.mu.Lock()
	m.request++
	if r.Header.Get("Authorization") != "Drop "+testTicket {
		m.mu.Unlock()
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	if m.status != 0 {
		code := m.status
		m.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(code)
		fmt.Fprintf(w, `{"code":"x","message":"server says %d"}`, code)
		return
	}
	if m.locked > 0 {
		m.locked--
		m.mu.Unlock()
		w.WriteHeader(http.StatusLocked)
		return
	}
	m.mu.Unlock()
	switch r.Method {
	case http.MethodHead:
		m.mu.Lock()
		var have []string
		for i := range m.parts {
			have = append(have, strconv.Itoa(i))
		}
		m.mu.Unlock()
		w.Header().Set("X-Vitals-Parts", strings.Join(have, ","))
		w.Header().Set("Content-Length", strconv.Itoa(len(m.data)))
		w.WriteHeader(http.StatusOK)
	case http.MethodPut:
		var start, end, size int64
		if r.Header.Get("Content-Range") == "bytes */0" {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if _, err := fmt.Sscanf(r.Header.Get("Content-Range"), "bytes %d-%d/%d", &start, &end, &size); err != nil || int(size) != len(m.data) {
			w.WriteHeader(http.StatusRequestedRangeNotSatisfiable)
			return
		}
		body, err := io.ReadAll(r.Body)
		if err != nil || int64(len(body)) != end-start+1 {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		m.mu.Lock()
		copy(m.data[start:], body)
		m.parts[int(start/dropPart)] = true
		m.puts = append(m.puts, int(start/dropPart))
		m.mu.Unlock()
		w.WriteHeader(http.StatusNoContent)
	case http.MethodGet:
		var from int64
		header := r.Header.Get("Range")
		m.mu.Lock()
		m.ranges = append(m.ranges, header)
		cut := m.cut
		m.cut = 0
		m.mu.Unlock()
		if header != "" {
			fmt.Sscanf(header, "bytes=%d-", &from)
			w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", from, len(m.data)-1, len(m.data)))
			w.Header().Set("Content-Length", strconv.Itoa(len(m.data)-int(from)))
			w.WriteHeader(http.StatusPartialContent)
		} else {
			w.Header().Set("Content-Length", strconv.Itoa(len(m.data)))
			w.WriteHeader(http.StatusOK)
		}
		rest := m.data[from:]
		if cut > 0 {
			w.Write(rest[:cut])
			w.(http.Flusher).Flush()
			panic(http.ErrAbortHandler)
		}
		if m.slow {
			for len(rest) > 0 && r.Context().Err() == nil {
				n := min(64<<10, len(rest))
				w.Write(rest[:n])
				w.(http.Flusher).Flush()
				rest = rest[n:]
				time.Sleep(50 * time.Millisecond)
			}
			return
		}
		w.Write(rest)
	}
}

func (m *fakeMac) count() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.request
}

type result struct {
	sum     string
	message string
	failed  bool
}

type listener struct {
	result   chan result
	stalls   chan string
	mu       sync.Mutex
	progress []int64
	routes   []string
}

func newListener() *listener {
	return &listener{result: make(chan result, 1), stalls: make(chan string, 16)}
}

func (l *listener) OnProgress(job string, done int64, total int64, route string) {
	l.mu.Lock()
	l.progress = append(l.progress, done)
	l.routes = append(l.routes, route)
	l.mu.Unlock()
}

func (l *listener) OnDone(job string, sum string) { l.result <- result{sum: sum} }

func (l *listener) OnError(job string, message string, retryable bool) {
	if retryable {
		l.stalls <- message
		return
	}
	l.result <- result{message: message, failed: true}
}

func (l *listener) wait(t *testing.T) result {
	t.Helper()
	select {
	case r := <-l.result:
		return r
	case <-time.After(30 * time.Second):
		t.Fatal("transfer never finished")
		return result{}
	}
}

func serve(t *testing.T, m *fakeMac) (string, string) {
	t.Helper()
	s := httptest.NewTLSServer(m)
	t.Cleanup(s.Close)
	cert, err := x509.ParseCertificate(s.TLS.Certificates[0].Certificate[0])
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(cert.RawSubjectPublicKeyInfo)
	return s.URL, base64.StdEncoding.EncodeToString(sum[:])
}

func random(n int) []byte {
	b := make([]byte, n)
	r := rand.NewChaCha8([32]byte{1})
	r.Read(b)
	return b
}

func job(size int, endpoints ...dropEndpoint) string {
	b, _ := json.Marshal(map[string]any{"job": "j", "title": "t", "endpoints": endpoints, "ticket": testTicket, "dropId": "drop-0001", "fileId": "f1", "size": size})
	return string(b)
}

func lan(url, pin string) dropEndpoint { return dropEndpoint{URL: url, Pin: &pin} }

func fdFor(t *testing.T, content []byte) (int, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "file")
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	fd, err := syscall.Dup(int(f.Fd()))
	if err != nil {
		t.Fatal(err)
	}
	return fd, path
}

func hash(b []byte) string {
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

func fast(t *testing.T) {
	backoff, stall := dropBackoff, dropStall
	dropBackoff, dropStall = 10*time.Millisecond, 2*time.Second
	t.Cleanup(func() { dropBackoff, dropStall = backoff, stall })
}

func TestUploadPinnedMatch(t *testing.T) {
	content := random(2*dropPart + 5)
	m := &fakeMac{data: make([]byte, len(content)), parts: map[int]bool{}}
	url, pin := serve(t, m)
	fd, _ := fdFor(t, content)
	l := newListener()
	if err := DropUpload("j", job(len(content), lan(url, pin)), fd, l); err != nil {
		t.Fatal(err)
	}
	r := l.wait(t)
	if r.failed {
		t.Fatalf("upload failed: %s", r.message)
	}
	if r.sum != hash(content) || !bytes.Equal(m.data, content) {
		t.Fatal("uploaded bytes differ")
	}
}

func TestPinMismatchRefused(t *testing.T) {
	m := &fakeMac{data: make([]byte, 10), parts: map[int]bool{}}
	url, _ := serve(t, m)
	fd, _ := fdFor(t, random(10))
	l := newListener()
	DropUpload("j", job(10, lan(url, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")), fd, l)
	r := l.wait(t)
	if !r.failed || m.count() != 0 {
		t.Fatalf("a wrong pin must be refused before any request: %+v, %d requests", r, m.count())
	}
}

func TestPinMismatchFallsBack(t *testing.T) {
	content := random(1000)
	m := &fakeMac{data: make([]byte, len(content)), parts: map[int]bool{}}
	url, pin := serve(t, m)
	fd, _ := fdFor(t, content)
	l := newListener()
	DropUpload("j", job(len(content), lan(url, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="), lan(url, pin)), fd, l)
	if r := l.wait(t); r.failed || !bytes.Equal(m.data, content) || m.count() != 2 {
		t.Fatalf("expected fallback to the second endpoint: %+v, %d requests", r, m.count())
	}
}

func TestUploadSendsOnlyMissingParts(t *testing.T) {
	content := random(4*dropPart + 100)
	m := &fakeMac{data: make([]byte, len(content)), parts: map[int]bool{3: true, 1: true}}
	copy(m.data[dropPart:2*dropPart], content[dropPart:])
	copy(m.data[3*dropPart:4*dropPart], content[3*dropPart:])
	url, pin := serve(t, m)
	fd, _ := fdFor(t, content)
	l := newListener()
	DropUpload("j", job(len(content), lan(url, pin)), fd, l)
	if r := l.wait(t); r.failed {
		t.Fatal(r.message)
	}
	slices.Sort(m.puts)
	if !slices.Equal(m.puts, []int{0, 2, 4}) || !bytes.Equal(m.data, content) {
		t.Fatalf("sent parts %v", m.puts)
	}
}

func TestEmptyUpload(t *testing.T) {
	m := &fakeMac{parts: map[int]bool{}}
	url, pin := serve(t, m)
	fd, _ := fdFor(t, nil)
	l := newListener()
	DropUpload("j", job(0, lan(url, pin)), fd, l)
	if r := l.wait(t); r.failed || r.sum != hash(nil) {
		t.Fatalf("%+v", r)
	}
}

func TestDownloadResumesAfterCut(t *testing.T) {
	fast(t)
	content := random(dropPart + 12345)
	m := &fakeMac{data: content, cut: 5 << 20}
	url, pin := serve(t, m)
	fd, path := fdFor(t, nil)
	l := newListener()
	DropDownload("j", job(len(content), lan(url, pin)), fd, l)
	r := l.wait(t)
	if r.failed {
		t.Fatal(r.message)
	}
	got, _ := os.ReadFile(path)
	if r.sum != hash(content) || !bytes.Equal(got, content) {
		t.Fatal("downloaded bytes differ")
	}
	if len(m.ranges) != 2 || m.ranges[1] != fmt.Sprintf("bytes=%d-", 5<<20) {
		t.Fatalf("ranges %q", m.ranges)
	}
}

func TestDownloadRehashesWhatIsOnDisk(t *testing.T) {
	content := random(3<<20 + 7)
	m := &fakeMac{data: content}
	url, pin := serve(t, m)
	fd, path := fdFor(t, content[:1<<20])
	l := newListener()
	DropDownload("j", job(len(content), lan(url, pin)), fd, l)
	r := l.wait(t)
	got, _ := os.ReadFile(path)
	if r.failed || r.sum != hash(content) || !bytes.Equal(got, content) {
		t.Fatalf("%+v", r)
	}
	if !slices.Equal(m.ranges, []string{fmt.Sprintf("bytes=%d-", 1<<20)}) {
		t.Fatalf("ranges %q", m.ranges)
	}
}

func TestLockedBacksOffThenFinishes(t *testing.T) {
	fast(t)
	content := random(1000)
	m := &fakeMac{data: make([]byte, len(content)), parts: map[int]bool{}, locked: 3}
	url, pin := serve(t, m)
	fd, _ := fdFor(t, content)
	l := newListener()
	DropUpload("j", job(len(content), lan(url, pin)), fd, l)
	if r := l.wait(t); r.failed || !bytes.Equal(m.data, content) {
		t.Fatalf("%+v", r)
	}
	if len(l.stalls) != 1 || <-l.stalls != "Paused" {
		t.Fatal("a 423 must be reported once as a retryable pause")
	}
	if m.count() < 5 {
		t.Fatalf("expected retries, got %d requests", m.count())
	}
}

func TestFinalStatusesStopAtOnce(t *testing.T) {
	for _, code := range []int{401, 403, 404, 405, 409, 410, 416, 422, 507} {
		m := &fakeMac{data: make([]byte, 10), parts: map[int]bool{}, status: code}
		url, pin := serve(t, m)
		fd, _ := fdFor(t, nil)
		l := newListener()
		DropDownload("j", job(10, lan(url, pin)), fd, l)
		if r := l.wait(t); !r.failed || m.count() != 1 || r.message != fmt.Sprintf("server says %d", code) {
			t.Fatalf("%d: %+v after %d requests", code, r, m.count())
		}
	}
}

func TestUnreachableStallsAndKeepsTrying(t *testing.T) {
	fast(t)
	m := &fakeMac{data: make([]byte, 10), parts: map[int]bool{}}
	s := httptest.NewTLSServer(m)
	url := s.URL
	s.Close()
	fd, _ := fdFor(t, random(10))
	l := newListener()
	DropUpload("j", job(10, lan(url, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")), fd, l)
	select {
	case message := <-l.stalls:
		if message != "Can't reach your Mac" {
			t.Fatal(message)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("no stall reported")
	}
	select {
	case r := <-l.result:
		t.Fatalf("the job must keep trying after a stall: %+v", r)
	case <-time.After(300 * time.Millisecond):
	}
	DropCancel("j")
	if r := l.wait(t); r.message != "Cancelled" {
		t.Fatalf("%+v", r)
	}
}

func TestShortFileFailsUpload(t *testing.T) {
	m := &fakeMac{data: make([]byte, 1000), parts: map[int]bool{}}
	url, pin := serve(t, m)
	fd, _ := fdFor(t, random(600))
	l := newListener()
	DropUpload("j", job(1000, lan(url, pin)), fd, l)
	if r := l.wait(t); !r.failed || r.message != "Can't read the file" {
		t.Fatalf("%+v", r)
	}
}

func TestCancel(t *testing.T) {
	content := random(8 << 20)
	m := &fakeMac{data: content, slow: true}
	url, pin := serve(t, m)
	fd, _ := fdFor(t, nil)
	l := newListener()
	DropDownload("j", job(len(content), lan(url, pin)), fd, l)
	time.Sleep(300 * time.Millisecond)
	DropCancel("j")
	r := l.wait(t)
	if !r.failed || r.message != "Cancelled" {
		t.Fatalf("%+v", r)
	}
	if err := DropDownload("j", job(len(content), lan(url, pin)), mustFd(t), newListener()); err != nil {
		t.Fatalf("a cancelled job id must be reusable: %v", err)
	}
	DropCancel("j")
}

func mustFd(t *testing.T) int {
	fd, _ := fdFor(t, nil)
	return fd
}

func TestProgressIsThrottled(t *testing.T) {
	content := random(8 << 20)
	m := &fakeMac{data: content, slow: true}
	url, pin := serve(t, m)
	fd, _ := fdFor(t, nil)
	l := newListener()
	start := time.Now()
	DropDownload("j", job(len(content), lan(url, pin)), fd, l)
	if r := l.wait(t); r.failed {
		t.Fatal(r.message)
	}
	elapsed := time.Since(start).Seconds()
	if limit := int(elapsed*4) + 1; len(l.progress) > limit || len(l.progress) == 0 {
		t.Fatalf("%d progress events in %.1fs", len(l.progress), elapsed)
	}
	if l.routes[0] != "lan" {
		t.Fatalf("route %s", l.routes[0])
	}
}
