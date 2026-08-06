# lips-realized module. Generated from a ground decision base; do not edit.
{ config, lib, pkgs, ... }:
{
  # <-d2 via r3
  security.acme.acceptTerms = true;
  # <-d3 via r4
  security.acme.defaults.email = "admin@example.com";
  # <-d1.2 via r2
  services.nginx.enable = true;
  # <-d2 via r3
  services.nginx.virtualHosts.blog.enableACME = true;
  # <-d2 via r3
  services.nginx.virtualHosts.blog.forceSSL = true;
  # <-d1.1 via r1
  services.nginx.virtualHosts.blog.root = "/var/www/blog";
  # <-d1.2 via r2
  services.nginx.virtualHosts.blog.serverName = "blog.example.com";
}
