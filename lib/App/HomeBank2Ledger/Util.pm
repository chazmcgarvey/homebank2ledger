package App::HomeBank2Ledger::Util;
# ABSTRACT: Miscellaneous utility functions

use warnings;
use strict;

use Exporter qw(import);

our $VERSION = '9999.999'; # VERSION

our @EXPORT_OK = qw(commify);

=func commify

    $commified = commify($num);
    $commified = commify($num, $comma_char);

Just another commify subroutine.

=cut

sub commify {
    my $num   = shift;
    my $comma = shift || ',';

    my $str = reverse $num;
    $str =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1$comma/g;

    return scalar reverse $str;
}

1;
