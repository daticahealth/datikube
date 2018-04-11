package auth

import (
	"encoding/json"
	"net/http"
)

// SigninResponse represents the successful response that can come from signin. This can either be
// a directly successful user signin, or a response signifying that an MFA token is required.
type SigninResponse struct {
	ID               string   `json:"id"`
	Email            string   `json:"email"`
	SessionToken     string   `json:"sessionToken"`
	MFAID            string   `json:"mfaID"`
	MFATypes         []string `json:"mfaTypes"`
	MFAPreferredType string   `json:"mfaPreferredType"`
	MFAChallenge     string   `json:"mfaChallenge"`
}

// MFARequired returns true if MFA is required for this user.
func (r *SigninResponse) MFARequired() bool {
	return r.MFAID != ""
}

// User returns the user object represented by this signin response.
func (r *SigninResponse) User() *User {
	if r.MFARequired() {
		return nil
	}
	return &User{
		ID:           r.ID,
		Email:        r.Email,
		SessionToken: r.SessionToken,
	}
}

type signinRequest struct {
	Identifier string `json:"identifier"`
	Password   string `json:"password"`
}

// SignIn attempts to sign a user in.
func (auth *CoreAuth) SignIn(email, password string) (*SigninResponse, error) {
	status, resp, err := auth.makeRequest(http.MethodPost, "/auth/signin", "", &signinRequest{
		Identifier: email,
		Password:   password,
	})
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, ConvertError(resp)
	}
	sr := &SigninResponse{}
	err = json.Unmarshal(resp, sr)
	if err != nil {
		return nil, err
	}
	return sr, nil
}

type mfaSigninRequest struct {
	OTP string `json:"otp"`
}

// MFASignIn attempts to complete the signin process for an MFA-enabled user.
func (auth *CoreAuth) MFASignIn(mfaID, otp string) (*User, error) {
	status, resp, err := auth.makeRequest(http.MethodPost, "/auth/signin/mfa/"+mfaID, "", &mfaSigninRequest{OTP: otp})
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, ConvertError(resp)
	}
	user := &User{}
	err = json.Unmarshal(resp, user)
	if err != nil {
		return nil, err
	}
	return user, nil
}
