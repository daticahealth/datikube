package auth

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"time"
)

// CoreAuth handles all authentication-related functionality to the Core API.
type CoreAuth struct {
	host string
}

// New builds a new CoreAuth instance.
func New(host string) *CoreAuth {
	return &CoreAuth{host: host}
}

func buildHeaders(token string) map[string][]string {
	b := make([]byte, 32)
	rand.Read(b)
	headers := map[string][]string{
		"Accept":              {"application/json"},
		"Content-Type":        {"application/json"},
		"X-Request-Nonce":     {base64.StdEncoding.EncodeToString(b)},
		"X-Request-Timestamp": {fmt.Sprintf("%d", time.Now().Unix())},
	}
	if token != "" {
		headers["Authorization"] = []string{"Bearer " + token}
	}
	return headers
}

// CoreError represents an error given by the Core API.
type CoreError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// Error complies with the error interface.
func (ce CoreError) Error() string {
	return fmt.Sprintf("Auth API error %d: %s", ce.Code, ce.Message)
}

// ConvertError formats an error response from the Core API. The returned error will be an instance of CoreError if so.
func ConvertError(resp []byte) error {
	ce := CoreError{}
	err := json.Unmarshal(resp, &ce)
	if err != nil {
		return err
	}
	return ce
}

func (auth *CoreAuth) makeRequest(method, path, token string, body interface{}) (int, []byte, error) {
	bodyBytes, err := json.Marshal(body)
	if err != nil {
		return 0, nil, err
	}
	req, err := http.NewRequest(method, auth.host+path, bytes.NewReader(bodyBytes))
	if err != nil {
		return 0, nil, err
	}
	req.Header = buildHeaders(token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, nil, err
	}

	defer resp.Body.Close()
	respBody, err := ioutil.ReadAll(resp.Body)
	return resp.StatusCode, respBody, err
}
