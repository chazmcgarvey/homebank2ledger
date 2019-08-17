package App::HomeBank2Ledger::Formatter::Beancount;
# ABSTRACT: Beancount formatter

=head1 DESCRIPTION

This is a formatter for L<Beancount|http://furius.ca/beancount/>.

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
my $UNKNOWN_DATE = '0001-01-01';

sub _croak { require Carp; Carp::croak(@_) }

sub format {
    my $self   = shift;
    my $ledger = shift;

    my @out = (
        $self->format_header,
        $self->format_accounts($ledger),
        $self->format_commodities($ledger),
        # $self->format_payees,
        # $self->format_tags,
        $self->format_transactions($ledger),
    );

    return join($/, map { rtrim($_) } @out);
}

=method format_header

    @lines = $formatter->format_header;

Get formatted header. For example,

    ; Name: My Finances
    ; File: path/to/finances.xhb

=cut

sub format_header {
    my $self = shift;

    my @out;

    if (my $name = $self->name) {
        push @out, "; Name: $name";
    }
    if (my $file = $self->file) {
        push @out, "; File: $file";
    }

    push @out, '';

    return @out;
}

=method format_accounts

    @lines = $formatter->format_accounts($ledger);

Get formatted accounts. For example,

    2003-02-14 open Assets:Bank:Credit-Union:Savings
    2003-02-14 open Assets:Bank:Credit-Union:Checking
    ...

=cut

sub format_accounts {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    for my $account (sort @{$ledger->accounts}) {
        my $oldest_transaction = $self->_find_oldest_transaction_by_account($account, $ledger);
        my $account_date = $oldest_transaction->{date} || $UNKNOWN_DATE;
        $account = $self->_format_account($account);

        push @out, "${account_date} open ${account}";
    }
    push @out, '';

    return @out;
}

=method format_commodities

    @lines = $formatter->format_commodities($ledger);

Get formattted commodities. For example,

    2003-02-14 commodity USD
        name: "US Dollar"
    ...

=cut

sub format_commodities {
    my $self   = shift;
    my $ledger = shift;

    my @out;

    for my $commodity (@{$ledger->commodities}) {
        my $oldest_transaction = $self->_find_oldest_transaction_by_commodity($commodity, $ledger);
        my $commodity_date = $oldest_transaction->{date} || $UNKNOWN_DATE;

        push @out, "${commodity_date} commodity $commodity->{iso}";
        push @out, '    name: '.$self->_format_string($commodity->{name}) if $commodity->{name};
    }

    push @out, '';

    return @out;
}

=method format_transactions

    @lines = $formatter->format_transactions($ledger);

Get formatted transactions. For example,

    2003-02-14 * "Opening Balance"
        Assets:Bank:Credit-Union:Savings           458.21 USD
        Assets:Bank:Credit-Union:Checking          194.17 USD
        Equity:Opening-Balances

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
    my $self        = shift;
    my $transaction = shift;

    my $account_width = $self->account_width;

    my $date        = $transaction->{date};
    my $status      = $transaction->{status};
    my $payee       = $transaction->{payee} || '';
    my $memo        = $transaction->{memo}  || '';
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

    push @out, sprintf('%s%s%s%s', $date,
        $status_symbol    && ' '.$status_symbol || ' *',   # status (or "txn") is required
        ($payee || $memo) && ' '.$self->_format_string($payee),
        $memo             && ' '.$self->_format_string($memo),
    );

    if (my %tags = map { $_ => 1 } map { @{$_->{tags} || []} } @postings) {
        my @tags = map { "#$_" } keys %tags;
        $out[-1] .= ' '.join(' ', @tags);
    }

    for my $posting (@postings) {
        my @line;

        my $posting_status_symbol = '';
        if (!$status_symbol) {
            $posting_status_symbol = $STATUS_SYMBOLS{$posting->{status} || ''} || '';
        }

        my $account = $self->_format_account($posting->{account});

        push @line, ($posting_status_symbol ? "  $posting_status_symbol " : '    ');
        push @line, sprintf("\%-${account_width}s", $account);
        push @line, '  ';
        push @line, $self->_format_amount($posting->{amount}, $posting->{commodity}) if defined $posting->{amount};

        push @out, join('', @line);
    }

    push @out, '';

    return @out;
}

sub _format_account {
    my $self = shift;
    my $account = shift;
    $account =~ s/[^A-Za-z0-9:]+/-/g;
    $account =~ s/-+/-/g;
    $account =~ s/(?:^|(?<=:))([a-z])/uc($1)/eg;
    return $account;
}

sub _format_string {
    my $self = shift;
    my $str  = shift;
    $str =~ s/"/\\"/g;
    return "\"$str\"";
}

sub _format_amount {
    my $self      = shift;
    my $amount    = shift;
    my $commodity = shift or _croak 'Must provide a valid currency';

    my $format = "\% .$commodity->{frac}f";
    my ($whole, $fraction) = split(/\./, sprintf($format, $amount));

    # beancount doesn't support different notations
    my $num = join('.', commify($whole), $fraction);

    $num = "$num $commodity->{iso}";

    return $num;
}

sub _find_oldest_transaction_by_account {
    my $self    = shift;
    my $account = shift;
    my $ledger  = shift;

    $account = $self->_format_account($account);

    my $oldest = $self->{oldest_transaction_by_account};
    if (!$oldest) {
        # build index
        for my $transaction (@{$ledger->transactions}) {
            for my $posting (@{$transaction->{postings}}) {
                my $account = $self->_format_account($posting->{account});

                if ($transaction->{date} lt ($oldest->{$account}{date} || '9999-99-99')) {
                    $oldest->{$account} = $transaction;
                }
            }
        }

        $self->{oldest_transaction_by_account} = $oldest;
    }

    return $oldest->{$account};
}

sub _find_oldest_transaction_by_commodity {
    my $self      = shift;
    my $commodity = shift;
    my $ledger    = shift;

    my $oldest = $self->{oldest_transaction_by_commodity};
    if (!$oldest) {
        # build index
        for my $transaction (@{$ledger->transactions}) {
            for my $posting (@{$transaction->{postings}}) {
                my $symbol = $posting->{commodity}{symbol};
                next if !$symbol;

                if ($transaction->{date} lt ($oldest->{$symbol}{date} || '9999-99-99')) {
                    $oldest->{$symbol} = $transaction;
                }
            }
        }

        $self->{oldest_transaction_by_commodity} = $oldest;
    }

    return $oldest->{$commodity->{symbol}};
}

1;
