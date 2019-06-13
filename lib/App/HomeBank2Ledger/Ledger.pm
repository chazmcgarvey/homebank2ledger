package App::HomeBank2Ledger::Ledger;
# ABSTRACT: Ledger data representation

=head1 SYNOPSIS

    my $ledger = App::HomeBank2Ledger::Ledger->new;

    $ledger->add_payees("Ann's Antiques", "Missy Automative");

    for my $payee (@{$ledger->payees}) {
        print "Payee: $payee\n";
    }

=head1 DESCRIPTION

This class provides a unified in-memory representation of a ledger, including associated metadata.

Here is a specification for the substructures:

=head2 account

This is a fully-qualified account name. Names may contain colons for representing a hierarchy of
accounts. Examples:

=for :list
* "Assets:Bank:Chase1234"
* "Liabilities:Credit Card:CapitalOne"

=head2 commodity

This is a hashref like this:

    {
        symbol  => '$',             # required
        iso     => 'USD',           # optional
        name    => 'US Dollar',     # optional
        format  => '$1000.00',      # optional
    }

=head2 payee

This is just a string with the name of a "payee" or memo/description/narration.

=head2 tag

This is just a string with the text of a tag.

=head2 transaction

This is a hashref like this:

    {
        date        => '2019-06-12',        # required
        payee       => 'Malcolm Reynolds',  # required
        status      => 'cleared',           # optional; can be "cleared" or "pending"
        memo        => 'Medical supplies',  # optional
        postings    => [                    # required
            {
                account     => 'Some Account',  # required
                amount      => '16.25',         # required for at least n-1 postings
                commodity   => {
                    symbol  => '$',
                    format  => '$1,000.00',
                    iso     => 'USD',
                    name    => 'US Dollar',
                    syprf   => 1,
                    dchar   => '.',
                    gchar   => ',',
                    frac    => 2,
                },
                payee       => 'Somebody',      # optional
                memo        => 'Whatever',      # optional
                status      => 'pending',       # optional; can be "cleared" or "pending"
                tags        => [qw(niska train-job)],
            },
            ...
        ],
    }

=cut

use warnings;
use strict;

our $VERSION = '9999.999'; # VERSION

=method new

    $ledger = App::HomeBank2Ledger::Ledger->new(%ledger_data);

Construct a new ledger instance.

=cut

sub new {
    my $class = shift;
    my %args  = @_;
    return bless {%args}, $class;
}

=attr accounts

Get an arrayref of accounts.

=attr commodities

Get an arrayref of commodities.

=attr payees

Get an arrayref of payees.

=attr tags

Get an arrayref of tags.

=attr transactions

Get an arrayref of transactions.

=cut

sub accounts     { shift->{accounts}     || [] }
sub commodities  { shift->{commodities}  || [] }
sub payees       { shift->{payees}       || [] }
sub tags         { shift->{tags}         || [] }
sub transactions { shift->{transactions} || [] }

=method add_accounts

Add accounts.

=method add_commodities

Add commodities.

=method add_payees

Add payees.

=method add_tags

Add tags.

=method add_transactions

Add transactions.

=cut

# TODO - These should validate incoming data.

sub add_accounts {
    my $self = shift;
    push @{$self->{accounts}}, @_;
}

sub add_commodities {
    my $self = shift;
    push @{$self->{commodities}}, @_;
}

sub add_payees {
    my $self = shift;
    push @{$self->{payees}}, @_;
}

sub add_tags {
    my $self = shift;
    push @{$self->{tags}}, @_;
}

sub add_transactions {
    my $self = shift;
    push @{$self->{transactions}}, @_;
}

1;
