package pactman

import (
	"fmt"
	"runtime"
)

// Version is the released version of this package, reported in the
// User-Agent header.
//
// A Go module's version is its git tag (go/vX.Y.Z), which the compiled code
// cannot read. The release workflow fails a tag that disagrees with this
// constant, so the number a server sees and the number published are the same.
const Version = "1.0.0"

// PackageName is the distribution name reported in the User-Agent header. It
// matches the name the other Pactman SDKs report, with the runtime telling
// them apart.
const PackageName = "pactman-nonprofit-check-plus"

// userAgent is "pactman-nonprofit-check-plus/<version> (go/<version>; <os>/<arch>)",
// so a server-side log can tell which SDK and which runtime made a call.
func userAgent() string {
	return fmt.Sprintf("%s/%s (go/%s; %s/%s)",
		PackageName, Version, runtime.Version(), runtime.GOOS, runtime.GOARCH)
}
