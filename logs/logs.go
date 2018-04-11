package logs

import (
	"fmt"
	"io"
	"os"
)

var verbose = false

// ConfigureVerbosity configures how verbose log printing should be.
func ConfigureVerbosity(v bool) {
	verbose = v
}

// Print logs a message to stdout, with optional format args.
func Print(message string, fmtArgs ...interface{}) {
	write(os.Stdout, message, fmtArgs)
}

// Printv logs a message to stdout, with optional format args, if verbosity is enabled.
func Printv(message string, fmtArgs ...interface{}) {
	if verbose {
		write(os.Stdout, "[verbose] "+message, fmtArgs)
	}
}

// Error logs a message to stderr, with optional format args.
func Error(message string, fmtArgs ...interface{}) {
	write(os.Stderr, message, fmtArgs)
}

func write(w io.Writer, message string, fmtArgs []interface{}) {
	s := message + "\n"
	if len(fmtArgs) > 0 {
		s = fmt.Sprintf(s, fmtArgs...)
	}
	w.Write([]byte(s))
}
