let
  system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOccenq6rA3lk3UtC0ywkJiiNV+76o6RQsfIQMY8cLw5 root@instance-20211029-1400";
in
{
  "discord-token-agora-prod.age".publicKeys = [ system ];
  "discord-token-secret-hitler.age".publicKeys = [ system ];

  "discord-config-agora-prod-msmtp.age".publicKeys = [ system ];
}
