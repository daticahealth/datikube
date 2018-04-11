package kubectl

import (
	"fmt"
	"io/ioutil"
	"os/exec"
	"strings"

	"github.com/daticahealth/datikube/logs"
)

const binary = "kubectl"

// VerifyInstallation returns an error if kubectl isn't installed.
func VerifyInstallation() error {
	_, err := exec.LookPath(binary)
	if err != nil {
		return fmt.Errorf("%[1]s not found. %[1]s must be installed for this command to be used", binary)
	}
	return nil
}

func invoke(args ...string) (*exec.Cmd, error) {
	if err := VerifyInstallation(); err != nil {
		return nil, err
	}
	logs.Printv("Running command: %s %s", binary, strings.Join(args, " "))
	return exec.Command(binary, args...), nil
}

func executePiped(args ...string) ([]byte, []byte, error) {
	cmd, err := invoke(args...)
	if err != nil {
		return nil, nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, nil, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, nil, err
	}
	err = cmd.Start()
	if err != nil {
		return nil, nil, err
	}
	stdoutOutput, err := ioutil.ReadAll(stdout)
	if err != nil {
		return nil, nil, err
	}
	stderrOutput, err := ioutil.ReadAll(stderr)
	if err != nil {
		return nil, nil, err
	}
	return stdoutOutput, stderrOutput, cmd.Wait()
}

// Execute runs a command against kubectl, returning the contents of stdout and printing any stderr.
func Execute(configPath string, args ...string) ([]byte, error) {
	if configPath != "" {
		args = append([]string{"--kubeconfig", configPath}, args...)
	}
	stdout, stderr, err := executePiped(args...)
	if err != nil {
		return nil, err
	}
	if len(stderr) > 0 {
		logs.Error(string(stderr))
	}
	logs.Printv("output: %s", string(stdout))
	return stdout, err
}
