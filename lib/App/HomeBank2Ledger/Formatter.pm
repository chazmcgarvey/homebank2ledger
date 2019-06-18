package App::HomeBank2Ledger::Formatter;
# ABSTRACT: Abstract class for formatting a ledger

=head1 SYNOPSIS

    my $formatter = App::HomeBank2Ledger::Formatter->new(
        type    => 'ledger',
    );
    print $formatter->format($ledger);

=head1 DESCRIPTION

This class formats L<ledger data|App::HomeBank2Ledger::Ledger> as for a file.

=head1 SEE ALSO

=for :list
* L<App::HomeBank2Ledger::Formatter::Beancount>
* L<App::HomeBank2Ledger::Formatter::Ledger>

=cut

use warnings;
use strict;

use Module::Load;
use Module::Pluggable search_path   => [__PACKAGE__],
                      sub_name      => 'available_formatters';

our $VERSION = '9999.999'; # VERSION

sub _croak { require Carp; Carp::croak(@_) }

=method new

    $formatter = App::HomeBank2Ledger::Formatter->new(type => $format);

Construct a new formatter object.

=cut

sub new {
    my $class = shift;
    my %args  = @_;

    my $package = __PACKAGE__;

    if ($class eq $package and my $type = $args{type}) {
        # factory
        for my $formatter ($class->available_formatters) {
            next if lc($formatter) ne lc("${package}::${type}");
            $class = $formatter;
            load $class;
            last;
        }
        _croak('Invalid formatter type') if $class eq $package;
    }

    return bless {%args}, $class;
}

=method format

    $str = $formatter->format($ledger);

Do the actual formatting of ledger data into a serialized form.

This must be overridden by subclasses.

=cut

sub format {
    die "Unimplemented\n";
}

=attr type

Get the type of formatter.

=attr name

Get the name or title of the ledger.

=attr file

Get the filepath where the ledger data came from.

=attr account_width

Get the number of characters to use for the account column.

=cut

sub type            { shift->{type} }
sub name            { shift->{name} }
sub file            { shift->{file} }
sub account_width   { shift->{account_width} || 40 }

1;
