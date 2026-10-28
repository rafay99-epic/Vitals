//go:build android

package tailnet

import (
	"net"
	"sync/atomic"
	"time"

	"tailscale.com/net/netmon"
)

// Android 11+ denies apps the netlink route dump that Go's net.Interfaces needs, so
// tsnet fails to start with "route ip+net: netlinkrib: permission denied". Tailscale's
// own fallback (feature/androidbin) is compiled out of cgo builds like this gomobile
// library, so register the same approach here: when the real list is unavailable,
// report one interface carrying the addresses the kernel picks for outbound traffic.
func init() {
	netmon.RegisterInterfaceGetter(interfaces)
}

// defaultIf is the interface Android last reported as the default route.
var defaultIf atomic.Pointer[string]

// setDefaultInterface records Android's default route. netmon only rebinds when the
// default interface is up in the list, so the stand-in interface below takes its name.
func setDefaultInterface(name string) {
	defaultIf.Store(&name)
	netmon.UpdateLastKnownDefaultRouteInterface(name)
}

func interfaces() ([]netmon.Interface, error) {
	if real, err := net.Interfaces(); err == nil {
		list := make([]netmon.Interface, 0, len(real))
		for i := range real {
			list = append(list, netmon.Interface{Interface: &real[i]})
		}
		return list, nil
	}
	var addrs []net.Addr
	// Dialing UDP sends no packets; it only asks the kernel for a route and source address.
	if ip := outboundIP("udp4", "8.8.8.8:53"); ip != nil {
		addrs = append(addrs, &net.IPNet{IP: ip, Mask: net.CIDRMask(32, 32)})
	}
	if ip := outboundIP("udp6", "[2001:4860:4860::8888]:53"); ip != nil {
		addrs = append(addrs, &net.IPNet{IP: ip, Mask: net.CIDRMask(128, 128)})
	}
	// With no route yet (airplane mode, a Wi-Fi handoff) report the interface as down rather than
	// failing, so the node still starts and netmon picks the network up when it comes back.
	var flags net.Flags
	if len(addrs) > 0 {
		flags = net.FlagUp | net.FlagRunning
	}
	name := "android"
	if last := defaultIf.Load(); last != nil && *last != "" {
		name = *last
	}
	return []netmon.Interface{{
		Interface: &net.Interface{Index: 1, MTU: 1500, Name: name, Flags: flags},
		AltAddrs:  addrs,
	}}, nil
}

func outboundIP(network, addr string) net.IP {
	conn, err := (&net.Dialer{Timeout: 2 * time.Second}).Dial(network, addr)
	if err != nil {
		return nil
	}
	defer conn.Close()
	local, ok := conn.LocalAddr().(*net.UDPAddr)
	if !ok || local.IP.IsLoopback() || local.IP.IsUnspecified() {
		return nil
	}
	return local.IP
}
