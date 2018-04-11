package cmd

import (
	"bufio"
	"fmt"
	"os"

	"github.com/howeyc/gopass"
	"github.com/daticahealth/datikube/auth"
	"github.com/daticahealth/datikube/logs"
)

func prompt(label string, echo bool) (string, error) {
	fmt.Print(label + ": ")
	if echo {
		scanner := bufio.NewScanner(os.Stdin)
		scanner.Scan()
		return scanner.Text(), scanner.Err()
	}
	passBytes, err := gopass.GetPasswd()
	return string(passBytes), err
}

func getUser(sessionToken string, forceReacquire bool) (*auth.User, error) {
	a := coreAuth()
	if !forceReacquire && sessionToken != "" {
		user, err := a.Verify(sessionToken)
		if err != nil {
			return nil, err
		}
		if user == nil {
			logs.Print("Your session has expired. You will need to sign in again to proceed.")
		} else {
			logs.Printv("Session verified successfully.")
			return user, nil
		}
	} else {
		logs.Printv("Forcing signin, as requested.")
	}
	return promptForSignin()
}

func promptForSignin() (*auth.User, error) {
	a := coreAuth()
	for {
		email, err := prompt("Email", true)
		if err != nil {
			return nil, err
		}
		password, err := prompt("Password", false)
		if err != nil {
			return nil, err
		}
		resp, err := a.SignIn(email, password)
		if err == nil {
			if resp.MFARequired() {
				return promptForMFA(resp)
			}
			return resp.User(), err
		}
		if ce, ok := err.(auth.CoreError); ok && ce.Code == 3011 {
			logs.Print(ce.Message)
		} else {
			return nil, err
		}
	}
}

func promptForMFA(sr *auth.SigninResponse) (*auth.User, error) {
	logs.Print("Your account as two-factor authentication enabled.")
	logs.Print("Enter your one-time password (%s) to complete signin.", sr.MFAPreferredType)
	otp, err := prompt("OTP", true)
	if err != nil {
		return nil, err
	}
	return coreAuth().MFASignIn(sr.MFAID, otp)
}
