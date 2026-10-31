defmodule PairingsEngine.Mailer do
  use Swoosh.Mailer, otp_app: :pairings_engine

  @doc """
  Delivers `email` with its bodies in CRLF line endings.

  Bodies are written as Elixir heredocs, so they end their lines with a bare
  LF. SMTP wants CRLF, and gen_smtp quoted-printable-encodes every bare LF as
  `=0A`, which turns the whole message into one enormous encoded line. Gmail on
  Android shows that as an empty mail. Doing the conversion here, once, covers
  every notifier without touching a single template.
  """
  def deliver(email, config \\ []) do
    super(crlf(email), config)
  end

  @doc """
  The `{name, address}` every outgoing mail is sent from: `SMTP_FROM_NAME`
  (default "OpenPairings") and the `SMTP_USERNAME` address.
  """
  def from do
    {Application.get_env(:pairings_engine, :mail_from_name, "OpenPairings"),
     System.get_env("SMTP_USERNAME") || "contact@example.com"}
  end

  @doc "Returns `email` with CRLF line endings in its text and HTML bodies."
  def crlf(%Swoosh.Email{} = email) do
    %{email | text_body: crlf_text(email.text_body), html_body: crlf_text(email.html_body)}
  end

  @doc "Converts any mix of LF, CRLF and bare CR to CRLF, never doubling."
  def crlf_text(nil), do: nil

  def crlf_text(text) when is_binary(text) do
    String.replace(text, ~r/\r\n|\r|\n/, "\r\n")
  end
end
