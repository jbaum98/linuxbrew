class Gcc < Formula
  def arch
    if Hardware::CPU.type == :intel
      if MacOS.prefer_64_bit?
        "x86_64"
      else
        "i686"
      end
    elsif Hardware::CPU.type == :ppc
      if MacOS.prefer_64_bit?
        "powerpc64"
      else
        "powerpc"
      end
    end
  end

  def osmajor
    `uname -r`.chomp
  end

  desc "GNU compiler collection"
  homepage "https://gcc.gnu.org"
  url "http://ftpmirror.gnu.org/gcc/gcc-5.2.0/gcc-5.2.0.tar.bz2"
  mirror "https://ftp.gnu.org/gnu/gcc/gcc-5.2.0/gcc-5.2.0.tar.bz2"
  sha256 "5f835b04b5f7dd4f4d2dc96190ec1621b8d89f2dc6f638f9f8bc1b1014ba8cad"

  bottle do
    revision 1
    sha256 "ad5350f6197eacc3e70439c5c0dcc8118500bf909141ea49f78110f77b0d6d93" => :el_capitan
    sha256 "9cc95abd2144c8af4449c9610b0f6e22e5351b27edafe7af958d3757b7f96064" => :yosemite
    sha256 "1fe4d5663ef0ceec8faa388045cf81dbadd6970a8d45f517f4cadf9f13f96bb1" => :mavericks
    sha256 "80893dd79e0ec91e9705556dd65f46f0c0acbe45e7386d36d31f68295dcbd474" => :mountain_lion
  end

  option "with-java", "Build the gcj compiler"
  option "with-all-languages", "Enable all compilers and languages, except Ada"
  option "with-nls", "Build with native language support (localization)"
  option "with-jit", "Build the jit compiler"
  option "without-fortran", "Build without the gfortran compiler"
  # enabling multilib on a host that can't run 64-bit results in build failures
  if OS.mac?
    option "without-multilib", "Build without multilib support" if MacOS.prefer_64_bit?
  else
    option "with-multilib", "Build with multilib support"
  end

  depends_on "zlib" unless OS.mac?
  depends_on "binutils" if build.with? "glibc"
  depends_on "glibc" => :optional
  depends_on "gmp"
  depends_on "libmpc"
  depends_on "mpfr"
  depends_on "isl"
  depends_on "ecj" if build.with?("java") || build.with?("all-languages")

  if MacOS.version < :leopard && OS.mac?
    # The as that comes with Tiger isn't capable of dealing with the
    # PPC asm that comes in libitm
    depends_on "cctools" => :build
  end

  fails_with :gcc_4_0
  fails_with :llvm

  # GCC bootstraps itself, so it is OK to have an incompatible C++ stdlib
  cxxstdlib_check :skip

  # The bottles are built on systems with the CLT installed, and do not work
  # out of the box on Xcode-only systems due to an incorrect sysroot.
  def pour_bottle?
    MacOS::CLT.installed?
  end

  def version_suffix
    version.to_s.slice(/\d/)
  end

  # Fix for libgccjit.so linkage on Darwin
  # https://gcc.gnu.org/bugzilla/show_bug.cgi?id=64089
  patch :DATA if OS.mac?

  def install
    # GCC will suffer build errors if forced to use a particular linker.
    ENV.delete "LD"

    if OS.mac? && MacOS.version < :leopard
      ENV["AS"] = ENV["AS_FOR_TARGET"] = "#{Formula["cctools"].bin}/as"
    end

    if build.with? "all-languages"
      # Everything but Ada, which requires a pre-existing GCC Ada compiler
      # (gnat) to bootstrap. GCC 4.6.0 adds go as a language option, but it is
      # currently only compilable on Linux.
      languages = %w[c c++ objc obj-c++ fortran java jit]
    else
      # C, C++, ObjC compilers are always built
      languages = %w[c c++ objc obj-c++]

      languages << "fortran" if build.with? "fortran"
      languages << "java" if build.with? "java"
      languages << "jit" if build.with? "jit"
    end

    args = []
    args << "--build=#{arch}-apple-darwin#{osmajor}" if OS.mac?
    if build.with? "glibc"
      binutils = Formula["binutils"].prefix/"x86_64-unknown-linux-gnu/bin"
      args += [
        "--with-native-system-header-dir=#{HOMEBREW_PREFIX}/include",
        "--with-build-time-tools=#{binutils}",
        "--with-boot-ldflags=-static-libstdc++ -static-libgcc #{ENV["LDFLAGS"]}",
      ]
    end
    args += [
      "--prefix=#{prefix}",
      ("--libdir=#{lib}/gcc/#{version_suffix}" if OS.mac?),
      "--enable-languages=#{languages.join(",")}",
      # Make most executables versioned to avoid conflicts.
      "--program-suffix=-#{version_suffix}",
      "--with-gmp=#{Formula["gmp"].opt_prefix}",
      "--with-mpfr=#{Formula["mpfr"].opt_prefix}",
      "--with-mpc=#{Formula["libmpc"].opt_prefix}",
      "--with-isl=#{Formula["isl"].opt_prefix}",
    ]
    args += [
      "--with-system-zlib",
      "--enable-libstdcxx-time=yes",
      "--enable-stage1-checking",
      "--enable-checking=release",
      "--enable-lto",
      # Use 'bootstrap-debug' build configuration to force stripping of object
      # files prior to comparison during bootstrap (broken by Xcode 6.3).
      "--with-build-config=bootstrap-debug",
      "--disable-werror",
      "--with-pkgversion=Homebrew #{name} #{pkg_version} #{build.used_options*" "}".strip,
      "--with-bugurl=https://github.com/Homebrew/homebrew/issues"
    ]

    # "Building GCC with plugin support requires a host that supports
    # -fPIC, -shared, -ldl and -rdynamic."
    args << "--enable-plugin" if !OS.mac? || MacOS.version > :tiger

    # Otherwise make fails during comparison at stage 3
    # See: http://gcc.gnu.org/bugzilla/show_bug.cgi?id=45248
    args << "--with-dwarf2" if OS.mac? && MacOS.version < :leopard

    args << "--disable-nls" if build.without? "nls"

    if build.with?("java") || build.with?("all-languages")
      args << "--with-ecj-jar=#{Formula["ecj"].opt_share}/java/ecj.jar"
    end

    if build.without?("multilib") || !MacOS.prefer_64_bit?
      args << "--disable-multilib"
    else
      args << "--enable-multilib"
    end

    args << "--enable-host-shared" if build.with?("jit") || build.with?("all-languages")

    # Ensure correct install names when linking against libgcc_s;
    # see discussion in https://github.com/Homebrew/homebrew/pull/34303
    inreplace "libgcc/config/t-slibgcc-darwin", "@shlib_slibdir@", "#{HOMEBREW_PREFIX}/lib/gcc/#{version_suffix}"

    mkdir "build" do
      if OS.mac? && !MacOS::CLT.installed?
        # For Xcode-only systems, we need to tell the sysroot path.
        # "native-system-headers" will be appended
        args << "--with-native-system-header-dir=/usr/include"
        args << "--with-sysroot=#{MacOS.sdk_path}"
      end

      system "../configure", *args
      system "make", "bootstrap"
      system "make", "install"

      if build.with?("fortran") || build.with?("all-languages")
        bin.install_symlink bin/"gfortran-#{version_suffix}" => "gfortran"
      end

      if OS.linux?
        # Create cpp, gcc and g++ symlinks
        bin.install_symlink "cpp-#{version_suffix}" => "cpp"
        bin.install_symlink "gcc-#{version_suffix}" => "gcc"
        bin.install_symlink "g++-#{version_suffix}" => "g++"
      end
    end

    # Handle conflicts between GCC formulae and avoid interfering
    # with system compilers.
    # Since GCC 4.8 libffi stuff are no longer shipped.
    # Rename man7.
    Dir.glob(man7/"*.7") { |file| add_suffix file, version_suffix }
    # Even when suffixes are appended, the info pages conflict when
    # install-info is run. TODO fix this.
    info.rmtree

    # Rename java properties
    if build.with?("java") || build.with?("all-languages")
      config_files = [
        "#{lib}/gcc/#{version_suffix}/logging.properties",
        "#{lib}/gcc/#{version_suffix}/security/classpath.security",
        "#{lib}/gcc/#{version_suffix}/i386/logging.properties",
        "#{lib}/gcc/#{version_suffix}/i386/security/classpath.security"
      ]
      config_files.each do |file|
        add_suffix file, version_suffix if File.exist? file
      end
    end

    # Move lib64/* to lib/ on Linuxbrew
    lib64 = Pathname.new "#{lib}64"
    if lib64.directory?
      system "mv #{lib64}/* #{lib}/"
      rmdir lib64
      prefix.install_symlink "lib" => "lib64"
    end
  end

  def add_suffix(file, suffix)
    dir = File.dirname(file)
    ext = File.extname(file)
    base = File.basename(file, ext)
    File.rename file, "#{dir}/#{base}-#{suffix}#{ext}"
  end

  def post_install
    if OS.linux?
      # Create cc and c++ symlinks, unless they already exist
      homebrew_bin = Pathname.new "#{HOMEBREW_PREFIX}/bin"
      homebrew_bin.install_symlink "gcc" => "cc" unless (homebrew_bin/"cc").exist?
      homebrew_bin.install_symlink "g++" => "c++" unless (homebrew_bin/"c++").exist?

      # Create the GCC specs file
      # See https://gcc.gnu.org/onlinedocs/gcc/Spec-Files.html

      # Locate the specs file
      gcc = "gcc-#{version_suffix}"
      specs = Pathname.new(`#{bin}/#{gcc} -print-libgcc-file-name`).dirname/"specs"
      ohai "Creating the GCC specs file: #{specs}"
      raise "command failed: #{gcc} -print-libgcc-file-name" if $?.exitstatus != 0
      specs_orig = Pathname.new("#{specs}.orig")
      rm_f [specs_orig, specs]

      # Save a backup of the default specs file
      s = `#{bin}/#{gcc} -dumpspecs`
      raise "command failed: #{gcc} -dumpspecs" if $?.exitstatus != 0
      specs_orig.write s

      # Set the library search path
      if build.with?("glibc")
        s += "*link_libgcc:\n-nostdlib -L#{lib}/gcc/x86_64-unknown-linux-gnu/#{version} -L#{HOMEBREW_PREFIX}/lib\n\n"
      else
        s += "*link_libgcc:\n+ -L#{HOMEBREW_PREFIX}/lib\n\n"
      end
      s += "*link:\n+ -rpath #{HOMEBREW_PREFIX}/lib"

      # Set the dynamic linker
      glibc = Formula["glibc"]
      if glibc.installed?
        s += " --dynamic-linker #{glibc.opt_lib}/ld-linux-x86-64.so.2"
      end
      s += "\n\n"
      specs.write s
    end
  end

  def caveats
    if build.with?("multilib") then <<-EOS.undent
      GCC has been built with multilib support. Notably, OpenMP may not work:
        https://gcc.gnu.org/bugzilla/show_bug.cgi?id=60670
      If you need OpenMP support you may want to
        brew reinstall gcc --without-multilib
      EOS
    end
  end

  test do
    (testpath/"hello-c.c").write <<-EOS.undent
      #include <stdio.h>
      int main()
      {
        puts("Hello, world!");
        return 0;
      }
    EOS
    system "#{bin}/gcc-#{version_suffix}", "-o", "hello-c", "hello-c.c"
    assert_equal "Hello, world!\n", `./hello-c`

    (testpath/"hello-cc.cc").write <<-EOS.undent
      #include <iostream>
      int main()
      {
        std::cout << "Hello, world!" << std::endl;
        return 0;
      }
    EOS
    system "#{bin}/g++-#{version_suffix}", "-o", "hello-cc", "hello-cc.cc"
    assert_equal "Hello, world!\n", `./hello-cc`

    if build.with?("fortran") || build.with?("all-languages")
      fixture = <<-EOS.undent
        integer,parameter::m=10000
        real::a(m), b(m)
        real::fact=0.5

        do concurrent (i=1:m)
          a(i) = a(i) + fact*b(i)
        end do
        print *, "done"
        end
      EOS
      (testpath/"in.f90").write(fixture)
      system "#{bin}/gfortran", "-c", "in.f90"
      system "#{bin}/gfortran", "-o", "test", "in.o"
      assert_equal "done", `./test`.strip
    end
  end
end
__END__
diff --git a/gcc/jit/Make-lang.in b/gcc/jit/Make-lang.in
index 44d0750..4df2a9c 100644
--- a/gcc/jit/Make-lang.in
+++ b/gcc/jit/Make-lang.in
@@ -85,8 +85,7 @@ $(LIBGCCJIT_FILENAME): $(jit_OBJS) \
	     $(jit_OBJS) libbackend.a libcommon-target.a libcommon.a \
	     $(CPPLIB) $(LIBDECNUMBER) $(LIBS) $(BACKENDLIBS) \
	     $(EXTRA_GCC_OBJS) \
-	     -Wl,--version-script=$(srcdir)/jit/libgccjit.map \
-	     -Wl,-soname,$(LIBGCCJIT_SONAME)
+	     -Wl,-install_name,$(LIBGCCJIT_SONAME)

 $(LIBGCCJIT_SONAME_SYMLINK): $(LIBGCCJIT_FILENAME)
	ln -sf $(LIBGCCJIT_FILENAME) $(LIBGCCJIT_SONAME_SYMLINK)
diff --git a/gcc/jit/jit-playback.c b/gcc/jit/jit-playback.c
index 925fa86..01cfd4b 100644
--- a/gcc/jit/jit-playback.c
+++ b/gcc/jit/jit-playback.c
@@ -2416,6 +2416,15 @@ invoke_driver (const char *ctxt_progname,
      time.  */
   ADD_ARG ("-fno-use-linker-plugin");

+#if defined (DARWIN_X86) || defined (DARWIN_PPC)
+  /* OS X's linker defaults to treating undefined symbols as errors.
+     If the context has any imported functions or globals they will be
+     undefined until the .so is dynamically-linked into the process.
+     Ensure that the driver passes in "-undefined dynamic_lookup" to the
+     linker.  */
+  ADD_ARG ("-Wl,-undefined,dynamic_lookup");
+#endif
+
   /* pex argv arrays are NULL-terminated.  */
   argvec.safe_push (NULL);
