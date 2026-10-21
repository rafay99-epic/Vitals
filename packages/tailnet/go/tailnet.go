// Package tailnet runs an embedded Tailscale node inside the Vitals phone app and
// forwards a local TCP port to the Mac's Wi-Fi listener over the tailnet. The
// app speaks its normal Noise-encrypted route through that port.
package tailnet

import (
	"context"
	"errors"
	"io"
	"net"
	"sync"
	"time"

	"tailscale.com/tsnet"
)

var (
	mu     sync.Mutex
	server *tsnet.Server
	ln     net.Listener
)

// Start brings the node up with its state in dir. Safe to call twice.
func Start(dir, hostname string) error {
	mu.Lock()
	defer mu.Unlock()
	if server != nil {
		return nil
	}
	s := &tsnet.Server{Dir: dir, Hostname: hostname, Ephemeral: false}
	if err := s.Start(); err != nil {
		return err
	}
	server = s
	return nil
}

// State returns the backend state ("NeedsLogin", "Running", ...) and, when a
// login is needed, the URL to open.
func State() string {
	mu.Lock()
	s := server
	mu.Unlock()
	if s == nil {
		return "Stopped|"
	}
	lc, err := s.LocalClient()
	if err != nil {
		return "NoState|"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	st, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		return "NoState|"
	}
	return st.BackendState + "|" + st.AuthURL
}

// Forward listens on 127.0.0.1 and pipes every connection to target over the
// tailnet. Returns the local port. Replaces any earlier forward.
func Forward(target string) (int, error) {
	mu.Lock()
	defer mu.Unlock()
	if server == nil {
		return 0, errors.New("tailnet not started")
	}
	if ln != nil {
		ln.Close()
	}
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	ln = l
	s := server
	go func() {
		for {
			local, err := l.Accept()
			if err != nil {
				return
			}
			go pipe(s, local, target)
		}
	}()
	return l.Addr().(*net.TCPAddr).Port, nil
}

func pipe(s *tsnet.Server, local net.Conn, target string) {
	defer local.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	remote, err := s.Dial(ctx, "tcp", target)
	cancel()
	if err != nil {
		return
	}
	defer remote.Close()
	done := make(chan struct{}, 2)
	go func() { io.Copy(remote, local); done <- struct{}{} }()
	go func() { io.Copy(local, remote); done <- struct{}{} }()
	<-done
}

// Stop tears the node down and the forward with it.
func Stop() {
	mu.Lock()
	defer mu.Unlock()
	if ln != nil {
		ln.Close()
		ln = nil
	}
	if server != nil {
		server.Close()
		server = nil
	}
}
