class Gpg21 < Formula
  desc "GNU Privacy Guard: a free PGP replacement"
  homepage "https://www.gnupg.org/"
  url "https://gnupg.org/ftp/gcrypt/gnupg/gnupg-2.1.17.tar.bz2"
  mirror "https://www.mirrorservice.org/sites/ftp.gnupg.org/gcrypt/gnupg/gnupg-2.1.17.tar.bz2"
  sha256 "c5dc54db432209fa8f9bdb071c8fb60a765ff28e363150e30bdd4543160243cb"

  bottle do
    sha256 "54c56057f77131999c28c36b8f1c7634cc49d93547c52e979afcffb18c5e414d" => :sierra
    sha256 "3318380b33d6f8b96219885d5e633214160a91e067f4914c17c8755bc1910afb" => :el_capitan
    sha256 "aaafb15c59f8d81683a2122ad9d7bbf9df15b38ebf6f4b0ac416d2f06e044d05" => :yosemite
  end

  patch :DATA

  option "with-gpgsplit", "Additionally install the gpgsplit utility"
  option "without-libusb", "Disable the internal CCID driver"
  option "with-test", "Verify the build with `make check`"

  deprecated_option "without-libusb-compat" => "without-libusb"

  depends_on "pkg-config" => :build
  depends_on "sqlite" => :build if MacOS.version == :mavericks
  depends_on "npth"
  depends_on "gnutls"
  depends_on "libgpg-error"
  depends_on "libgcrypt"
  depends_on "libksba"
  depends_on "libassuan"
  depends_on "pinentry"
  depends_on "gettext"
  depends_on "adns"
  depends_on "libusb" => :recommended
  depends_on "readline" => :optional
  depends_on "homebrew/fuse/encfs" => :optional

  conflicts_with "gnupg2",
        :because => "GPG2.1.x is incompatible with the 2.0.x branch."
  conflicts_with "gpg-agent",
        :because => "GPG2.1.x ships an internal gpg-agent which it must use."
  conflicts_with "dirmngr",
        :because => "GPG2.1.x ships an internal dirmngr which it it must use."
  conflicts_with "fwknop",
        :because => "fwknop expects to use a `gpgme` with Homebrew/Homebrew's gnupg2."
  conflicts_with "gpgme",
        :because => "gpgme currently requires 1.x.x or 2.0.x."
  conflicts_with "homebrew/versions/gnupg21",
        :because => "they won't patch it so it works"

  def install
    # Undefined symbols libintl_bind_textdomain_codeset, etc.
    # Reported 19 Nov 2016 https://bugs.gnupg.org/gnupg/issue2846
    ENV.append "LDFLAGS", "-lintl"

    args = %W[
      --disable-dependency-tracking
      --disable-silent-rules
      --prefix=#{prefix}
      --sbindir=#{bin}
      --sysconfdir=#{etc}
      --enable-symcryptrun
      --with-pinentry-pgm=#{Formula["pinentry"].opt_bin}/pinentry
    ]

    args << "--disable-ccid-driver" if build.without? "libusb"
    args << "--with-readline=#{Formula["readline"].opt_prefix}" if build.with? "readline"

    # Adjust package name to fit our scheme of packaging both gnupg 1.x and
    # and 2.1.x and gpg-agent separately.
    inreplace "configure" do |s|
      s.gsub! "PACKAGE_NAME='gnupg'", "PACKAGE_NAME='gnupg2'"
      s.gsub! "PACKAGE_TARNAME='gnupg'", "PACKAGE_TARNAME='gnupg2'"
    end

    system "./configure", *args

    system "make"

    # Intermittent "FAIL: gpgtar.scm" and "FAIL: ssh.scm"
    # Reported 25 Jul 2016 https://bugs.gnupg.org/gnupg/issue2425
    # Starting in 2.1.16, "can't connect to the agent: IPC connect call failed"
    # Reported 19 Nov 2016 https://bugs.gnupg.org/gnupg/issue2847
    system "make", "check" if build.with? "test"

    system "make", "install"

    bin.install "tools/gpgsplit" => "gpgsplit2" if build.with? "gpgsplit"

    # Move man files that conflict with 1.x.
    mv share/"doc/gnupg2/FAQ", share/"doc/gnupg2/FAQ21"
    mv share/"doc/gnupg2/examples/gpgconf.conf", share/"doc/gnupg2/examples/gpgconf21.conf"
    mv share/"info/gnupg.info", share/"info/gnupg21.info"
    mv man7/"gnupg.7", man7/"gnupg21.7"
  end

  def post_install
    (var/"run").mkpath
  end

  def caveats; <<-EOS.undent
    Once you run the new gpg2 binary you will find it incredibly
    difficult to go back to using `gnupg2` from Homebrew/Homebrew.
    The new 2.1.x moves to a new keychain format that can't be
    and won't be understood by the 2.0.x branch or lower.

    If you use this `gnupg21` formula for a while and decide
    you don't like it, you will lose the keys you've imported since.
    For this reason, we strongly advise that you make a backup
    of your `~/.gnupg` directory.

    For full details of the changes, please visit:
      https://www.gnupg.org/faq/whats-new-in-2.1.html

    If you are upgrading to gnupg21 from gnupg2 you should execute:
      `killall gpg-agent && gpg-agent --daemon`
    After install. See:
      https://github.com/Homebrew/homebrew-versions/issues/681
    EOS
  end

  test do
    system bin/"gpgconf"
  end
end

__END__
diff --git a/dirmngr/dns-stuff.c b/dirmngr/dns-stuff.c
--- a/dirmngr/dns-stuff.c
+++ b/dirmngr/dns-stuff.c
@@ -478,7 +478,16 @@ libdns_init (void)
       if (err)
         {
           log_error ("failed to load '%s': %s\n", fname, gpg_strerror (err));
-          goto leave;
+          /* not fatal, nsswitch.conf is not used on all systems; assume
+           * classic behavior instead.  Our dns library states "bf" which tries
+           * DNS then Files, which is not classic; FreeBSD
+           * /usr/src/lib/libc/net/gethostnamadr.c defines default_src[] which
+           * is Files then DNS, which is. */
+          log_debug ("dns: fallback resolution order, files then DNS");
+          ld.resolv_conf->lookup[0] = 'f';
+          ld.resolv_conf->lookup[1] = 'b';
+          ld.resolv_conf->lookup[2] = '\0';
+          err = GPG_ERR_NO_ERROR;
         }
 
 #endif /* Unix */
@@ -732,6 +732,10 @@ resolve_name_libdns (const char *name, unsigned short port,
               err = gpg_error_from_syserror ();
               goto leave;
             }
+          /* Libdns appends the root zone part which is problematic
+           * for most other functions - strip it.  */
+          if (**r_canonname && (*r_canonname)[strlen (*r_canonname)-1] == '.')
+            (*r_canonname)[strlen (*r_canonname)-1] = 0;
         }
 
       dai = xtrymalloc (sizeof *dai + ent->ai_addrlen -1);
@@ -1899,6 +1903,13 @@ get_dns_cname_libdns (const char *name, char **r_cname)
   *r_cname = xtrystrdup (cname.host);
   if (!*r_cname)
     err = gpg_error_from_syserror ();
+  else
+    {
+      /* Libdns appends the root zone part which is problematic
+       * for most other functions - strip it.  */
+      if (**r_cname && (*r_cname)[strlen (*r_cname)-1] == '.')
+        (*r_cname)[strlen (*r_cname)-1] = 0;
+    }
 
  leave:
   dns_free (ans);
