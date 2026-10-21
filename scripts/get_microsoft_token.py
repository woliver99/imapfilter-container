#!/usr/bin/env python3
"""
scripts/get_microsoft_token.py
Interactive CLI helper to generate and verify a Microsoft OAuth 2.0 Refresh Token
for personal Hotmail / Outlook / Office365 accounts using Mozilla Thunderbird's
pre-authorized public Azure Client ID.

Zero external dependencies - uses standard library Python 3 only.
"""

import base64
import hashlib
import http.server
import imaplib
import json
import secrets
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser

# Mozilla Thunderbird's public Azure Client ID
CLIENT_ID = "9e5f94bc-e8a4-4e73-b8be-63364c29d753"
SCOPES = "offline_access https://outlook.office.com/IMAP.AccessAsUser.All"
AUTH_ENDPOINT = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
TOKEN_ENDPOINT = "https://login.microsoftonline.com/common/oauth2/v2.0/token"


class OAuthCallbackHandler(http.server.BaseHTTPRequestHandler):
    auth_code = None
    auth_error = None

    def log_message(self, format, *args):
        # Suppress noisy HTTP server request logs
        return

    def do_GET(self):
        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)

        if "code" in params:
            OAuthCallbackHandler.auth_code = params["code"][0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            html = """
            <!DOCTYPE html>
            <html>
            <head><title>Authorization Successful</title></head>
            <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; text-align: center; padding: 60px;">
                <h1 style="color: #107c41;">&#10004; Authorization Successful!</h1>
                <p style="font-size: 18px; color: #333;">Your Microsoft authentication code has been received.</p>
                <p style="color: #666;">You can safely close this browser window and return to your terminal.</p>
            </body>
            </html>
            """
            self.wfile.write(html.encode("utf-8"))
        elif "error" in params:
            OAuthCallbackHandler.auth_error = params.get("error_description", params["error"])[0]
            self.send_response(400)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            html = f"""
            <!DOCTYPE html>
            <html>
            <head><title>Authorization Failed</title></head>
            <body style="font-family: sans-serif; text-align: center; padding: 60px;">
                <h1 style="color: #d83b01;">&#10006; Authorization Failed</h1>
                <p>{OAuthCallbackHandler.auth_error}</p>
            </body>
            </html>
            """
            self.wfile.write(html.encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()


def find_free_port():
    import socket
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def generate_pkce():
    code_verifier = secrets.token_urlsafe(64)
    hashed = hashlib.sha256(code_verifier.encode("utf-8")).digest()
    code_challenge = base64.urlsafe_b64encode(hashed).decode("utf-8").rstrip("=")
    return code_verifier, code_challenge


def exchange_code_for_token(code, code_verifier, redirect_uri):
    payload = {
        "client_id": CLIENT_ID,
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "code_verifier": code_verifier,
        "scope": SCOPES,
    }
    encoded_data = urllib.parse.urlencode(payload).encode("utf-8")
    req = urllib.request.Request(
        TOKEN_ENDPOINT,
        data=encoded_data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        print(f"\n[ERROR] Token exchange failed with status {e.code}:\n{error_body}", file=sys.stderr)
        sys.exit(1)


def verify_imap_connection(username, access_token):
    print(f"\nTesting IMAP connection to outlook.office365.com:993 for {username}...")
    try:
        mail = imaplib.IMAP4_SSL("outlook.office365.com", 993)
        sasl_auth = f"user={username}\x01auth=Bearer {access_token}\x01\x01"
        encoded_sasl = base64.b64encode(sasl_auth.encode("utf-8")).decode("utf-8")

        mail.authenticate("XOAUTH2", lambda x: encoded_sasl)
        print("[SUCCESS] IMAP SASL XOAUTH2 authentication verified successfully!")
        mail.logout()
        return True
    except Exception as e:
        print(f"[WARNING] IMAP verification failed: {e}", file=sys.stderr)
        print("Note: The refresh token was still generated, but verify your email address is correct.")
        return False


def main():
    print("=" * 70)
    print(" Microsoft Account OAuth 2.0 Setup (Hotmail / Outlook / Office365)")
    print("=" * 70)
    print("This utility generates a modern authentication Refresh Token for your")
    print("Microsoft email account without requiring an Azure developer portal account.")
    print("=" * 70)

    # Prompt for email address
    username = ""
    if len(sys.argv) > 1:
        username = sys.argv[1].strip()
    while not username:
        username = input("\nEnter your Microsoft email address (e.g. user@hotmail.com): ").strip()

    # Ephemeral local web server for OAuth redirect callback
    port = 8080
    try:
        server = http.server.HTTPServer(("127.0.0.1", port), OAuthCallbackHandler)
    except OSError:
        port = find_free_port()
        server = http.server.HTTPServer(("127.0.0.1", port), OAuthCallbackHandler)

    redirect_uri = f"http://localhost:{port}"
    code_verifier, code_challenge = generate_pkce()

    params = {
        "client_id": CLIENT_ID,
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "response_mode": "query",
        "scope": SCOPES,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
        "login_hint": username,
    }
    auth_url = f"{AUTH_ENDPOINT}?{urllib.parse.urlencode(params)}"

    print(f"\n1. Starting local authentication listener on {redirect_uri}...")
    print("2. Opening your default web browser to Microsoft sign-in...")
    print("\nIf the browser does not open automatically, copy and paste this URL:")
    print("-" * 70)
    print(auth_url)
    print("-" * 70)

    webbrowser.open(auth_url)

    # Serve one request to capture the callback
    server_thread = threading.Thread(target=server.handle_request)
    server_thread.daemon = True
    server_thread.start()

    print("\nWaiting for Microsoft sign-in callback (or you may paste the redirect URL below)...")
    
    # Wait for either server to catch the callback or user to paste it manually
    while OAuthCallbackHandler.auth_code is None and OAuthCallbackHandler.auth_error is None and server_thread.is_alive():
        server_thread.join(timeout=1.0)

    auth_code = OAuthCallbackHandler.auth_code

    if not auth_code:
        if OAuthCallbackHandler.auth_error:
            print(f"\n[ERROR] Authorization error: {OAuthCallbackHandler.auth_error}", file=sys.stderr)
            sys.exit(1)
        else:
            manual_input = input("\nCallback not received automatically. Paste the full redirected URL here:\n").strip()
            if "code=" in manual_input:
                parsed = urllib.parse.parse_qs(urllib.parse.urlparse(manual_input).query)
                auth_code = parsed.get("code", [None])[0]

    if not auth_code:
        print("\n[ERROR] No authorization code found. Aborting.", file=sys.stderr)
        sys.exit(1)

    print("\nExchanging authorization code for tokens...")
    token_response = exchange_code_for_token(auth_code, code_verifier, redirect_uri)

    access_token = token_response.get("access_token")
    refresh_token = token_response.get("refresh_token")

    if not refresh_token:
        print("\n[ERROR] No refresh_token returned in response:\n" + json.dumps(token_response, indent=2), file=sys.stderr)
        sys.exit(1)

    # Test IMAP connection
    verify_imap_connection(username, access_token)

    print("\n" + "=" * 70)
    print(" AUTHENTICATION SUCCESSFUL! Add the following to your .env file:")
    print("=" * 70)
    print(f"ACCOUNT_1_USER={username}")
    print(f"ACCOUNT_1_REFRESH_TOKEN={refresh_token}")
    print("ACCOUNT_1_SERVER=outlook.office365.com")
    print("ACCOUNT_1_PORT=993")
    print("ACCOUNT_1_SSL=auto")
    print("ACCOUNT_1_RULES=whitelist,newsletter")
    print("=" * 70)
    print("\nDone! Start or restart your container with: docker compose up -d")


if __name__ == "__main__":
    main()
