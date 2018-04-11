package auth

// User represents a Core API user.
type User struct {
	ID           string `json:"id"`
	Email        string `json:"email"`
	SessionToken string `json:"sessionToken"`
}
