import json
import os
import unittest
from unittest import mock

import handler


class ContactHandlerTests(unittest.TestCase):
    def setUp(self):
        self.env = mock.patch.dict(os.environ, {
            "ALLOWED_ORIGINS": "https://buhaj.eu,https://www.buhaj.eu",
            "RECAPTCHA_SECRET_KEY": "secret",
            "RECAPTCHA_EXPECTED_HOSTNAMES": "buhaj.eu,www.buhaj.eu",
            "SES_FROM_EMAIL": "contact@buhaj.eu",
            "SES_TO_EMAIL": "contact@buhaj.eu",
            "AWS_REGION_NAME": "eu-west-3",
        }, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def event(self, **changes):
        payload = {
            "name": "Jan Kowalski", "email": "jan@example.com", "phone": "",
            "projectType": "oak-table", "message": "Proszę o wycenę.", "locale": "pl",
            "consent": True, "projectId": "oak-table", "company": "", "recaptchaToken": "token",
        }
        payload.update(changes.pop("payload", {}))
        event = {
            "headers": {"origin": "https://buhaj.eu", "content-type": "application/json"},
            "requestContext": {"http": {"method": "POST", "sourceIp": "203.0.113.1"}},
            "body": json.dumps(payload),
        }
        event.update(changes)
        return event

    def status(self, event):
        return handler.handler(event, None)["statusCode"]

    def test_success(self):
        with mock.patch.object(handler, "_verify_recaptcha", return_value=(True, "ok")), \
             mock.patch.object(handler, "_send_email") as send:
            self.assertEqual(self.status(self.event()), 200)
            send.assert_called_once()

    def test_rejects_bad_origin(self):
        event = self.event()
        event["headers"]["origin"] = "https://attacker.example"
        self.assertEqual(self.status(event), 403)

    def test_rejects_invalid_and_oversized_payloads(self):
        self.assertEqual(self.status(self.event(body="{")), 400)
        self.assertEqual(self.status(self.event(body="x" * (handler.MAX_BODY_BYTES + 1))), 400)
        self.assertEqual(self.status(self.event(body="%%%", isBase64Encoded=True)), 400)
        self.assertEqual(self.status(self.event(payload={"email": "invalid"})), 400)
        self.assertEqual(self.status(self.event(payload={"consent": False})), 400)

    def test_rejects_honeypot(self):
        self.assertEqual(self.status(self.event(payload={"company": "bot"})), 400)

    def test_handles_captcha_failures(self):
        with mock.patch.object(handler, "_verify_recaptcha", return_value=(False, "invalid")):
            self.assertEqual(self.status(self.event()), 403)
        with mock.patch.object(handler, "_verify_recaptcha", return_value=(False, "unavailable")):
            self.assertEqual(self.status(self.event()), 503)

    def test_missing_configuration_is_safe(self):
        os.environ.pop("ALLOWED_ORIGINS")
        response = handler.handler(self.event(), None)
        self.assertEqual(response["statusCode"], 500)
        self.assertNotIn("secret", response["body"])

    def test_handles_delivery_failure_without_internal_details(self):
        with mock.patch.object(handler, "_verify_recaptcha", return_value=(True, "ok")), \
             mock.patch.object(handler, "_send_email", side_effect=RuntimeError("secret detail")):
            response = handler.handler(self.event(), None)
        self.assertEqual(response["statusCode"], 503)
        self.assertNotIn("secret detail", response["body"])

    def test_recaptcha_hostname_must_match(self):
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self, limit): return b'{"success":true,"hostname":"attacker.example"}'

        with mock.patch("urllib.request.urlopen", return_value=Response()):
            self.assertEqual(handler._verify_recaptcha("token", ""), (False, "invalid"))


if __name__ == "__main__":
    unittest.main()
