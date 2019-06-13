package App::HomeBank2Ledger::Formatter::Beancount;
# ABSTRACT: Beancount formatter

=head1 DESCRIPTION

This is a formatter for L<Beancount|http://furius.ca/beancount/>.

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
        # $self->_format_payees,
        # $self->_format_tags,
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

    for my $account (sort @{$ledger->accounts}) {
        $account = $self->_munge_account($account);
        push @out, "1970-01-01 open $account";  # TODO pick better date?
    }
    push @out, '';

    return @out;
}

sub _format_commodities {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    for my $commodity (@{$ledger->commodities}) {
        push @out, "1970-01-01 commodity $commodity->{iso}";    # TODO
        push @out, "    name: \"$commodity->{name}\"" if $commodity->{name};
    }

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
    my $self        = shift;
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
    push @out, "${date} ${symbol}\"${payee}\" \"$memo\"";   # TODO handle proper quoting
    $out[-1] =~ s/\h+$//;

    if (my %tags = map { $_ => 1 } map { @{$_->{tags} || []} } @postings) {
        my @tags = map { "#$_" } keys %tags;
        $out[-1] .= "  ".join(' ', @tags);
    }

    for my $posting (@postings) {
        my @line;

        my $posting_status_symbol = '';
        if (!$status_symbol) {
            $posting_status_symbol = $STATUS_SYMBOLS{$posting->{status} || ''} || '';
        }

        my $account = $self->_munge_account($posting->{account});

        push @line, ($posting_status_symbol ? "  $posting_status_symbol " : '    ');
        push @line, sprintf("\%-${account_width}s", $account);
        push @line, '  ';
        push @line, $self->_format_amount($posting->{amount}, $posting->{commodity}) if defined $posting->{amount};

        push @out, join('', @line);
        $out[-1] =~ s/\h+$//;

        # if (my $payee = $posting->{payee}) {
        #     push @out, "      ; Payee: $payee";
        # }
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

    # beancount doesn't support different notations
    my $num = join('.', commify($whole), $fraction);

    $num = "$num $commodity->{iso}";

    return $num;
}

sub _munge_account {
    my $self = shift;
    my $account = shift;
    $account =~ s/[^A-Za-z0-9:]+/-/g;
    $account =~ s/-+/-/g;
    $account =~ s/(?:^|(?<=:))([a-z])/uc($1)/eg;
    return $account;
}

1;
