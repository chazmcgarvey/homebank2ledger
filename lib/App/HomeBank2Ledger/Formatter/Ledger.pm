package App::HomeBank2Ledger::Formatter::Ledger;
# ABSTRACT: Ledger formatter

=head1 DESCRIPTION

This is a formatter for L<Ledger|https://www.ledger-cli.org/>.

=head1 SEE ALSO

L<App::HomeBank2Ledger::Formatter>

=cut

use warnings;
use strict;

use App::HomeBank2Ledger::Util qw(commify rtrim);

use parent 'App::HomeBank2Ledger::Formatter';

our $VERSION = '9999.999'; # VERSION

my %STATUS_SYMBOLS = (
    cleared => '*',
    pending => '!',
);

sub _croak { require Carp; Carp::croak(@_) }

sub format {
    my $self   = shift;
    my $ledger = shift;

    my @out = (
        $self->format_header,
        $self->format_accounts($ledger),
        $self->format_commodities($ledger),
        $self->format_payees($ledger),
        $self->format_tags($ledger),
        $self->format_transactions($ledger),
    );

    return join($/, map { rtrim($_) } @out);
}

=method format_header

    @lines = $formatter->format_header;

Get formatted header. For example,

    ; Converted from finances.xhb using homebank2ledger 0.001

=cut

sub format_header {
    my $self = shift;

    my @out;

    if (my $name = $self->name) {
        push @out, "; Name: $name";
    }

    my $file = $self->file;
    push @out, "; Converted from ${file} using homebank2ledger ${VERSION}";

    push @out, '';

    return @out;
}

=method format_accounts

    @lines = $formatter->format_accounts($ledger);

Get formatted accounts. For example,

    account Assets:Bank:Credit Union:Savings
    account Assets:Bank:Credit Union:Checking
    ...

=cut

sub format_accounts {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    push @out, map { "account $_" } sort @{$ledger->accounts};
    push @out, '';

    return @out;
}

=method format_commodities

    @lines = $formatter->format_commodities($ledger);

Get formattted commodities. For example,

    commodity $
        note US Dollar
        format $  1,000.00
        alias USD
    ...

=cut

sub format_commodities {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    for my $commodity (@{$ledger->commodities}) {
        push @out, "commodity $commodity->{symbol}";
        push @out, "    note $commodity->{name}"     if $commodity->{name};
        push @out, "    format $commodity->{format}" if $commodity->{format};
        push @out, "    alias $commodity->{iso}"     if $commodity->{iso};
    }

    push @out, '';

    return @out;
}

=method format_payees

    @lines = $formatter->format_payees($ledger);

Get formatted payees. For example,

    payee 180 Tacos
    ...

=cut

sub format_payees {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    push @out, map { "payee $_" } sort @{$ledger->payees};
    push @out, '';

    return @out;
}

=method format_tags

    @lines = $formatter->format_tags($ledger);

Get formatted tags. For example,

    tag yapc
    ...

=cut

sub format_tags {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    push @out, map { "tag $_" } sort @{$ledger->tags};
    push @out, '';

    return @out;
}

=method format_transactions

    @lines = $formatter->format_transactions($ledger);

Get formatted transactions. For example,

    2003-02-14 * Opening Balance
        Assets:Bank:Credit Union:Savings          $  458.21
        Assets:Bank:Credit Union:Checking         $  194.17
        Equity:Opening Balances

    ...

=cut

sub format_transactions {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    for my $transaction (@{$ledger->transactions}) {
        push @out, $self->_format_transaction($transaction);
    }

    return @out;
}

sub _format_transaction {
    my $self = shift;
    my $transaction = shift;

    my $account_width = $self->account_width;

    my $date        = $transaction->{date};
    my $status      = $transaction->{status};
    my $payee       = $self->_format_string($transaction->{payee} || '');
    my $memo        = $self->_format_string($transaction->{memo}  || '');
    my @postings    = @{$transaction->{postings}};

    my @out;

    # figure out the Ledger transaction status
    my $status_symbol = $STATUS_SYMBOLS{$status || ''};
    if (!$status_symbol) {
        my %posting_statuses = map { ($_->{status} || '') => 1 } @postings;
        if (keys(%posting_statuses) == 1) {
            my ($status) = keys %posting_statuses;
            $status_symbol = $STATUS_SYMBOLS{$status || 'none'} || '';
        }
    }

    $payee =~ s/(?:  )|\t;/ ;/g;    # don't turn into a memo

    push @out, sprintf('%s%s%s%s', $date,
        $status_symbol && " ${status_symbol}",
        $payee         && " $payee",
        $memo          && "  ; $memo",
    );

    for my $posting (@postings) {
        my @line;

        my $posting_status_symbol = '';
        if (!$status_symbol) {
            $posting_status_symbol = $STATUS_SYMBOLS{$posting->{status} || ''} || '';
        }

        push @line, ($posting_status_symbol ? "  $posting_status_symbol " : '    ');
        push @line, sprintf("\%-${account_width}s", $posting->{account});
        push @line, '  ';
        push @line, $self->_format_amount($posting->{amount}, $posting->{commodity}) if defined $posting->{amount};

        push @out, join('', @line);

        if (my $posting_payee = $posting->{payee}) {
            $posting_payee = $self->_format_string($posting_payee);
            push @out, "      ; Payee: $posting_payee" if $posting_payee ne $payee;
        }

        if (my @tags = @{$posting->{tags} || []}) {
            push @out, '      ; :'.join(':', @tags).':';
        }
    }

    push @out, '';

    return @out;
}

sub _format_string {
    my $self = shift;
    my $str  = shift;
    $str =~ s/\v//g;
    return $str;
}

sub _format_amount {
    my $self      = shift;
    my $amount    = shift;
    my $commodity = shift or _croak 'Must provide a valid currency';

    my $format = "\% .$commodity->{frac}f";
    my ($whole, $fraction) = split(/\./, sprintf($format, $amount));

    my $num = join($commodity->{dchar}, commify($whole, $commodity->{gchar}), $fraction);

    $num = $commodity->{syprf} ? "$commodity->{symbol} $num" : "$num $commodity->{symbol}";

    return $num;
}

1;
