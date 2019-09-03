#!/usr/bin/env perl

# This script creates a fatpacked version of homebank2ledger. Much of this code was inspired by or
# blatantly copied from cpanminus build scripts, written by Tatsuhiko Miyagawa.

use warnings FATAL => 'all';
use strict;
use autodie ':all';

use App::FatPacker ();
use Cwd;
use File::Find;
use File::Path;
use File::pushd;
use Module::CoreList;


my $distdir = shift;

my $script_name = 'bin/homebank2ledger';
my $libdir = 'lib';

if ($distdir) {
    if (-d "$distdir/blib") {
        $script_name = "$distdir/blib/script/homebank2ledger";
        $libdir = "$distdir/blib/lib";
    }
    else {
        $script_name = "$distdir/$script_name";
        $libdir = "$distdir/$libdir";
    }
}

make_fatlib();
make_script();
exit;


BEGIN {
    # IO::Socket::IP requires newer Socket, which is C-based
    $ENV{PERL_HTTP_TINY_IPV4_ONLY} = 1;
}

END {
    no autodie;
    unlink('homebank2ledger.tmp');
    rmtree('.fatpack-build');
    rmtree('fatlib');
}


sub find_requires {
    my $file = shift;

    my %requires;
    open my $in, "<", $file;
    while (<$in>) {
        /^\s*(?:use|require) (\S+)[^;]*;\s*$/
          and $requires{$1} = 1;
    }

    keys %requires;
}

sub mod_to_pm {
    local $_ = shift;
    s!::!/!g;
    "$_.pm";
}

sub pm_to_mod {
    local $_ = shift;
    s!/!::!g;
    s/\.pm$//;
    $_;
}

sub in_lib {
    my $file = shift;
    -e "$libdir/$file";
}

sub is_core {
    my $module = shift;
    exists $Module::CoreList::version{5.008001}{$module};
}

sub exclude_modules {
    my($modules, $except) = @_;
    my %exclude = map { $_ => 1 } @$except;
    [ grep !$exclude{$_}, @$modules ];
}

sub pack_modules {
    my($path, $modules, $no_trace) = @_;

    $modules = exclude_modules($modules, $no_trace);

    my $packer = App::FatPacker->new;
    my @requires = grep !is_core(pm_to_mod($_)), grep /\.pm$/, split /\n/,
      $packer->trace(use => $modules, args => ['-e', 1]);
    push @requires, map mod_to_pm($_), @$no_trace;

    my @packlists = $packer->packlists_containing(\@requires);
    for my $packlist (@packlists) {
        print "Packing $packlist\n";
    }
    $packer->packlists_to_tree($path, \@packlists);
}

sub make_fatlib {
    my @modules = grep !in_lib(mod_to_pm($_)), find_requires($script_name);

    pack_modules(cwd . '/fatlib', \@modules, []);

    use Config;
    print "Remove fatlib/$Config{archname}\n";
    rmtree("fatlib/$Config{archname}");
    rmtree("fatlib/POD2");

    my $want = sub {
        if (/\.pod$/) {
            print "Remove $_\n";
            unlink $_;
        }
    };

    find({ wanted => $want, no_chdir => 1 }, 'fatlib');
}


sub generate_file {
    my($base, $target, $fatpack) = @_;

    open my $in,  "<", $base;
    open my $out, ">", "$target.tmp";

    print STDERR "Generating $target from $base\n";

    while (<$in>) {
        s|^#!\h*perl|#!/usr/bin/env perl|;
        s|^# FATPACK.*|$fatpack|;
        print $out $_;
    }

    close $out;

    eval { unlink $target };
    rename "$target.tmp", $target;
}

sub make_script {
    mkdir '.fatpack-build';
    system qw(cp -r fatlib), $libdir, qw(.fatpack-build/);

    my $fatpack_compact = do {
        my $dir = pushd '.fatpack-build';

        my @files;
        my $want = sub {
            push @files, $_ if /\.pm$/;
            if (/\.pod$/) {
                print "Remove $_\n";
                unlink $_;
            }
        };

        find({ wanted => $want, no_chdir => 1 }, 'fatlib', 'lib');
        system qw(perlstrip --cache -v), @files;

        `fatpack file`;
    };

    my $filename = $script_name;
    $filename =~ s!^.*/!!;

    generate_file($script_name, $filename, $fatpack_compact);
    chmod 0755, $filename;
}

