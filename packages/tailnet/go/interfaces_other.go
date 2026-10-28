//go:build !android

package tailnet

// setDefaultInterface is Android only: other platforms' netmon reads the default route itself.
func setDefaultInterface(string) {}
