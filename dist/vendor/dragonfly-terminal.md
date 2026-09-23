# Use BSD terminal ioctls on DragonFly

termbox-go v1.1.2 omits DragonFly from its BSD build constraint. This selects
`unix.TCGETS` and `unix.TCSETS`, which do not exist on DragonFly, and prevents
mongostat from compiling. Include DragonFly in the BSD file using `TIOCGETA`
and `TIOCSETA`, and exclude it from the non-BSD file. Other targets keep their
existing selection.

Apply after `go mod vendor`, alongside the SDK telemetry patch. Run the offline
release tests and cross-compile mongostat with `GOOS=dragonfly GOARCH=amd64
CGO_ENABLED=0` against the patched vendor tree.
