package App::HomeBank2Ledger::Formatter::Ledger;
# ABSTRACT: Ledger formatter

=head1 DESCRIPTION

This is a formatter for L<Ledger|https://www.ledger-cli.org/>.

=head1 SEE ALSO

L<App::HomeBank2Ledger::Formatter>

=cut

use warnings;
use strict;

use App::HomeBank2Ledger::Util qw(commify);

use parent 'App::HomeBank2Ledger::Formatter';

our $VERSION = '9999.999'; # VERSION

my %STATUS_SYMBOLS = (
    cleared => '*',
    pending => '!',
);

sub format {
    my $self   = shift;
    my $ledger = shift;

    my @out = (
        $self->_format_header,
        $self->_format_accounts($ledger),
        $self->_format_commodities($ledger),
        $self->_format_payees($ledger),
        $self->_format_tags($ledger),
        $self->_format_transactions($ledger),
    );

    return join($/, @out);
}

sub _format_header {
    my $self = shift;

    my @out;

    my $file = $self->file;
    push @out, "; Converted from $file using homebank2ledger ${VERSION}";

    if (my $name = $self->name) {
        push @out, "; Name: $name";
    }

    push @out, '';

    return @out;
}

sub _format_accounts {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    push @out, map { "account $_" } sort @{$ledger->accounts};
    push @out, '';

    return @out;
}

sub _format_commodities {
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

sub _format_payees {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    push @out, map { "payee $_" } sort @{$ledger->payees};
    push @out, '';

    return @out;
}

sub _format_tags {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    push @out, map { "tag $_" } sort @{$ledger->tags};
    push @out, '';

    return @out;
}

sub _format_transactions {
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
    my $payee       = $transaction->{payee} || 'No Payee TODO';
    my $memo        = $transaction->{memo} || '';
    my @postings    = @{$transaction->{postings}};

    my @out;

    # figure out the Ledger transaction status
    my $status_symbol = $STATUS_SYMBOLS{$status || ''};
    if (!$status_symbol) {
        my %posting_statuses = map { ($_->{status} || '') => 1 } @postings;
        if (keys(%posting_statuses) == 1) {
            my ($status) = keys %posting_statuses;
            $status_symbol = $STATUS_SYMBOLS{$status || 'none'} || '';
            $status_symbol .= ' ' if $status_symbol;
        }
    }

    my $symbol = $status_symbol ? "${status_symbol} " : '';
    push @out, "${date} ${symbol}${payee}  ; $memo";
    $out[-1] =~ s/\h+$//;

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
        $out[-1] =~ s/\h+$//;

        if (my $payee = $posting->{payee}) {
            push @out, "      ; Payee: $payee";
        }

        if (my @tags = @{$posting->{tags} || []}) {
            push @out, "      ; :".join(':', @tags).":";
        }
    }

    push @out, '';

    return @out;
}

sub _format_amount {
    my $self      = shift;
    my $amount    = shift;
    my $commodity = shift;

    # _croak 'Must provide a valid currency' if !$commodity;

    my $format = "\% .$commodity->{frac}f";
    my ($whole, $fraction) = split(/\./, sprintf($format, $amount));

    my $num = join($commodity->{dchar}, commify($whole, $commodity->{gchar}), $fraction);

    $num = $commodity->{syprf} ? "$commodity->{symbol} $num" : "$num $commodity->{symbol}";

    return $num;
}

1;
