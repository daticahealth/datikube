package auth

import (
	"encoding/json"
	"net/http"

	"github.com/daticahealth/datikube/logs"
)

// Verify checks if a session token is still valid, returning the authenticated user or nil if the
// passed token has expired.
func (auth *CoreAuth) Verify(sessionToken string) (*User, error) {
	status, resp, err := auth.makeRequest(http.MethodGet, "/auth/verify", sessionToken, nil)
	if err != nil {
		return nil, err
	}
	if status == http.StatusUnauthorized {
		logs.Printv("Verify received status 401")
		return nil, nil
	} else if status != http.StatusOK {
		return nil, ConvertError(resp)
	}
	user := &User{}
	err = json.Unmarshal(resp, user)
	if err != nil {
		return nil, err
	}
	user.SessionToken = sessionToken
	return user, nil
}
