defmodule PairingsEngine.MailerCrlfTest do
  @moduledoc """
  Bodies are LF heredocs; gen_smtp quoted-printable-encodes a bare LF as
  `=0A`, which Gmail on Android renders as an empty mail. The Mailer converts
  to CRLF before delivery.
  """
  use ExUnit.Case, async: true
  import Swoosh.TestAssertions

  alias PairingsEngine.Accounts.{User, UserNotifier}
  alias PairingsEngine.Mailer

  @user %User{email: "arbiter@example.com", confirmed_at: ~U[2026-01-01 00:00:00Z]}
  @url "https://openpairings.example.org/users/log-in/" <> String.duplicate("abcdefgh", 12)

  defp smtp_body(email), do: Swoosh.Adapters.SMTP.Helpers.body(email, [])

  test "the SMTP body of a delivered mail has no =0A and keeps the link intact" do
    assert {:ok, _} = UserNotifier.deliver_login_instructions(@user, @url)

    assert_email_sent(fn email ->
      body = smtp_body(email)
      refute body =~ "=0A"
      # QP soft line breaks are legal; the link must survive decoding.
      decoded = String.replace(body, "=
", "")
      assert decoded =~ "\r\n" <> @url <> "\r\n"
      true
    end)
  end

  test "crlf_text never doubles an existing CRLF" do
    assert Mailer.crlf_text("a\nb\r\nc\rd") == "a\r\nb\r\nc\r\nd"
    assert Mailer.crlf_text(Mailer.crlf_text("a\nb")) == "a\r\nb"
    assert Mailer.crlf_text(nil) == nil
  end
end
