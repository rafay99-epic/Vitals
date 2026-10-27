// Package tailnet runs an embedded Tailscale node inside the Vitals phone app and
// forwards a local TCP port to the Mac's Wi-Fi listener over the tailnet. The
// app speaks its normal Noise-encrypted route through that port.
package tailnet

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

	"tailscale.com/client/local"
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
	// Tailscale's log policy looks for a logs folder in desktop-OS places that do not
	// exist inside an Android app and panics when it finds none. Point it inside dir.
	logs := filepath.Join(dir, "logs")
	if err := os.MkdirAll(logs, 0o700); err != nil {
		return err
	}
	if err := os.Setenv("TS_LOGS_DIR", logs); err != nil {
		return err
	}
	s := &tsnet.Server{Dir: dir, Hostname: hostname, Ephemeral: false}
	if err := s.Start(); err != nil {
		return err
	}
	server = s
	return nil
}

// localClient returns the running node's LocalAPI client.
func localClient() (*local.Client, error) {
	mu.Lock()
	s := server
	mu.Unlock()
	if s == nil {
		return nil, errors.New("tailnet not started")
	}
	return s.LocalClient()
}

// Login asks the control server for a new sign-in URL, which State then reports.
// tsnet does this itself only for a node that starts signed out; a saved node whose
// key expired or that was removed from the tailnet sits in NeedsLogin without one.
func Login() error {
	lc, err := localClient()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return lc.StartLoginInteractive(ctx)
}

// NetworkChanged tells the node the phone switched networks (Wi-Fi, cellular, none).
// ifName is the new default interface, "" when offline. Android gives netmon no change
// feed, only a 10-minute poll, so without this the node keeps its old path.
func NetworkChanged(ifName string) {
	setDefaultInterface(ifName)
	mu.Lock()
	s := server
	mu.Unlock()
	if s == nil {
		return
	}
	if mon, ok := s.Sys().NetMon.GetOK(); ok {
		mon.InjectEvent()
	}
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

// SignOut logs the node out of its tailnet, stops it and deletes its state in dir, so
// the next Start signs in from scratch. Logging out is best effort; the state goes anyway.
func SignOut(dir string) error {
	if lc, err := localClient(); err == nil {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		lc.Logout(ctx)
		cancel()
	}
	Stop()
	return os.RemoveAll(dir)
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
