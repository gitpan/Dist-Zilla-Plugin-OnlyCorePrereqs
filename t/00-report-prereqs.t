#!perl

use strict;
use warnings;

# This test was generated by Dist::Zilla::Plugin::Test::ReportPrereqs 0.014

use Test::More tests => 1;

use ExtUtils::MakeMaker;
use File::Spec::Functions;
use List::Util qw/max first/;
use Scalar::Util qw/blessed/;
use version;

# hide optional CPAN::Meta modules from prereq scanner
# and check if they are available
my $cpan_meta = "CPAN::Meta";
my $cpan_meta_pre = "CPAN::Meta::Prereqs";
my $cpan_meta_req = "CPAN::Meta::Requirements";
my $HAS_CPAN_META = eval "require $cpan_meta"; ## no critic
my $HAS_CPAN_META_REQ = eval "require $cpan_meta_req; $cpan_meta_req->VERSION('2.120900')";

# Verify requirements?
my $DO_VERIFY_PREREQS = 1;

sub _merge_prereqs {
    my ($collector, $prereqs) = @_;

    # CPAN::Meta::Prereqs object
    if (blessed $collector eq $cpan_meta_pre) {
        return $collector->with_merged_prereqs(
            CPAN::Meta::Prereqs->new( $prereqs )
        );
    }

    # Raw hashrefs
    for my $phase ( keys %$prereqs ) {
        for my $type ( keys %{ $prereqs->{$phase} } ) {
            for my $module ( keys %{ $prereqs->{$phase}{$type} } ) {
                $collector->{$phase}{$type}{$module} = $prereqs->{$phase}{$type}{$module};
            }
        }
    }

    return $collector;
}

my @include = qw(
  feature
  CPAN::Meta::Validator
);

my @exclude = qw(

);

# Add static prereqs to the included modules list
my $static_prereqs = do 't/00-report-prereqs.dd';

### XXX: Assume these are Runtime Requires
my $static_prereqs_requires = $static_prereqs->{runtime}{requires};
for my $mod (@include) {
    $static_prereqs_requires->{$mod} = 0 unless exists $static_prereqs_requires->{$mod};
}

# Merge all prereqs (either with ::Prereqs or a hashref)
my $full_prereqs = _merge_prereqs(
    ( $HAS_CPAN_META ? $cpan_meta_pre->new : {} ),
    $static_prereqs
);

# Add dynamic prereqs to the included modules list (if we can)
my $source = first { -f } 'MYMETA.json', 'MYMETA.yml';
if ( $source && $HAS_CPAN_META ) {
    if ( my $meta = eval { CPAN::Meta->load_file($source) } ) {
        $full_prereqs = _merge_prereqs($full_prereqs, $meta->prereqs);
    }
}
else {
    $source = 'static metadata';
}

my @full_reports;
my @dep_errors;
my $req_hash = $HAS_CPAN_META ? $full_prereqs->as_string_hash : $full_prereqs;

for my $phase ( qw(configure build test runtime develop) ) {
    next unless $req_hash->{$phase};
    next if ($phase eq 'develop' and not $ENV{AUTHOR_TESTING});

    for my $type ( qw(requires recommends suggests conflicts) ) {
        next unless $req_hash->{$phase}{$type};

        my $title = ucfirst($phase).' '.ucfirst($type);
        my @reports = [qw/Module Want Have/];

        for my $mod ( sort keys %{ $req_hash->{$phase}{$type} } ) {
            next if $mod eq 'perl';
            next if first { $_ eq $mod } @exclude;

            my $file = $mod;
            $file =~ s{::}{/}g;
            $file .= ".pm";
            my $prefix = first { -e catfile($_, $file) } @INC;

            my $want = $req_hash->{$phase}{$type}{$mod};
            $want = "undef" unless defined $want;
            $want = "any" if !$want && $want == 0;

            my $req_string = $want eq 'any' ? 'any version required' : "version '$want' required";

            if ($prefix) {
                my $have = MM->parse_version( catfile($prefix, $file) );
                $have = "undef" unless defined $have;
                push @reports, [$mod, $want, $have];

                if ( $DO_VERIFY_PREREQS && $type eq 'requires' ) {
                    if ( ! defined eval { version->parse($have) } ) {
                        push @dep_errors, "$mod version '$have' cannot be parsed ($req_string)";
                    }
                    elsif ( ! $full_prereqs->requirements_for( $phase, $type )->accepts_module( $mod => $have ) ) {
                        push @dep_errors, "$mod version '$have' is not in required range '$want'";
                    }
                }
            }
            else {
                push @reports, [$mod, $want, "missing"];

                if ( $DO_VERIFY_PREREQS && $type eq 'requires' ) {
                    push @dep_errors, "$mod is not installed ($req_string)";
                }
            }
        }

        if ( @reports ) {
            push @full_reports, "=== $title ===\n\n";

            my $ml = max map { length $_->[0] } @reports;
            my $wl = max map { length $_->[1] } @reports;
            my $hl = max map { length $_->[2] } @reports;
            splice @reports, 1, 0, ["-" x $ml, "-" x $wl, "-" x $hl];

            push @full_reports, map { sprintf("    %*s %*s %*s\n", -$ml, $_->[0], $wl, $_->[1], $hl, $_->[2]) } @reports;
            push @full_reports, "\n";
        }
    }
}

if ( @full_reports ) {
    diag "\nVersions for all modules listed in $source (including optional ones):\n\n", @full_reports;
}

if ( @dep_errors ) {
    diag join("\n",
        "\n*** WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING ***\n",
        "The following REQUIRED prerequisites were not satisfied:\n",
        @dep_errors,
        "\n"
    );
}

pass;

# vim: ts=4 sts=4 sw=4 et:
