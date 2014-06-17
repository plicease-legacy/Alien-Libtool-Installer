package Alien::Libtool::Installer;

use strict;
use warnings;

# ABSTRACT: Installer for libtool
# VERSION

sub versions_available
{
  require HTTP::Tiny;
  my $url = "http://ftp.gnu.org/gnu/libtool/";
  my $response = HTTP::Tiny->new->get($url);
  
  die sprintf("%s %s %s", $response->{status}, $response->{reason}, $url)
    unless $response->{success};

  my @versions;
  # TODO dupes
  push @versions, [$1,$2,$4] while $response->{content} =~ /libtool-([1-9][0-9]*)\.([0-9]+)(\.([0-9]+)|)\.tar.gz/g;
  @versions = map { join '.', grep { defined $_ } @$_ }  sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] || ($a->[2]||0) <=> ($b->[2]||0) } @versions;
}

sub fetch
{
  my($class, %options) = @_;
  
  my $dir = $options{dir} || eval { require File::Temp; File::Temp::tempdir( CLEANUP => 1 ) };

  require HTTP::Tiny;  
  my $version = $options{version} || do {
    my @versions = $class->versions_available;
    die "unable to determine latest version from listing"
      unless @versions > 0;
    $versions[-1];
  };

  if(defined $ENV{ALIEN_LIBTOOL_INSTALL_MIRROR})
  {
    my $fn = File::Spec->catfile($ENV{ALIEN_LIBTOOL_INSTALL_MIRROR}, "libtool-$version.tar.gz");
    return wantarray ? ($fn, $version) : $fn;
  }

  my $url = "http://ftp.gnu.org/gnu/libtool/libtool-$version.tar.gz";
  
  my $response = HTTP::Tiny->new->get($url);
  
  die sprintf("%s %s %s", $response->{status}, $response->{reason}, $url)
    unless $response->{success};
  
  require File::Spec;
  
  my $fn = File::Spec->catfile($dir, "libtool-$version.tar.gz");
  
  open my $fh, '>', $fn;
  binmode $fh;
  print $fh $response->{content};
  close $fh;
  
  wantarray ? ($fn, $version) : $fn;
}

sub build_requires
{
  my %prereqs = (
    'HTTP::Tiny'   => 0,
    'Archive::Tar' => 0,
  );
  
  if($^O eq 'MSWin32')
  {
    $prereqs{'Alien::MSYS'} = '0.07';
  }
  
  \%prereqs;
}

sub system_requires
{
  my %prereqs = ();
  \%prereqs;
}

sub system_install
{
  die 'TODO';
}

sub _msys
{
  my($sub) = @_;
  require Config;
  if($^O eq 'MSWin32')
  {
    if($Config::Config{cc} !~ /cl(\.exe)?$/i)
    {
      require Alien::MSYS;
      return Alien::MSYS::msys(sub{ $sub->('make') });
    }
  }
  $sub->($Config::Config{make});
}

sub build_install
{
  my($class, $prefix, %options) = @_;
  
  $options{test} ||= 'compile';
  die "test must be one of compile, ffi or both"
    unless $options{test} =~ /^(compile|ffi|both)$/;
  die "need an install prefix" unless $prefix;
  
  $prefix =~ s{\\}{/}g;
  
  my $dir = $options{dir} || do { require File::Temp; File::Temp::tempdir( CLEANUP => 1 ) };
  
  require Archive::Tar;
  my $tar = Archive::Tar->new;
  $tar->read($options{tar} || $class->fetch);
  
  require Cwd;
  my $save = Cwd::getcwd();
  
  chdir $dir;  
  my $build = eval {
  
    $tar->extract;

    chdir do {
      opendir my $dh, '.';
      my(@list) = grep !/^\./,readdir $dh;
      close $dh;
      die "unable to find source in build root" if @list == 0;
      die "confused by multiple entries in the build root" if @list > 1;
      $list[0];
    };
  
    _msys(sub {
      # TODO this will only work with gcc
      my($make) = @_;
      system 'sh', 'configure', "--prefix=$prefix", '--with-pic', '--enable-shared';
      die "configure failed" if $?;
      system $make, 'all';
      die "make all failed" if $?;
      system $make, 'install';
      die "make install failed" if $?;
    });

    my $build = bless {
      bin     => File::Spec->catdir($prefix, 'bin'),
    }, $class;
    
    $build;
  };
  
  my $error = $@;
  chdir $save;
  die $error if $error;
  $build;
}

sub bin  { shift->{bin}  }
sub error { shift->{error} }

1;

