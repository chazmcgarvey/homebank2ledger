package File::HomeBank;
# ABSTRACT: Parse HomeBank files

=head1 SYNOPSIS

    # Functional:

    use File::HomeBank qw(parse_file);

    my $raw_data = parse_file('path/to/homebank.xhb');

    # Or OOP:

    my $homebank = File::HomeBank->new(file => 'path/to/homebank.xhb');

    for my $account (@{$homebank->accounts}) {
        print "Found account named $account->{name}\n";
    }

=head1 DESCRIPTION

This module parses L<HomeBank|http://homebank.free.fr/> files.

=cut

use warnings;
use strict;

use App::HomeBank2Ledger::Util qw(commify);
use Exporter qw(import);
use Scalar::Util qw(refaddr);
use Time::Piece;
use XML::Parser::Lite;

our $VERSION = '9999.999'; # VERSION

our @EXPORT_OK = qw(parse_string parse_file);

sub _croak { require Carp; Carp::croak(@_) }
sub _usage { _croak("Usage: @_\n") }

my %ACCOUNT_TYPES = (
    0   => 'none',
    1   => 'bank',
    2   => 'cash',
    3   => 'asset',
    4   => 'creditcard',
    5   => 'liability',
    6   => 'stock',
    7   => 'mutualfund',
    8   => 'income',
    9   => 'expense',
    10  => 'equity',
);
my %ACCOUNT_FLAGS = (
    0   => 'oldbudget',
    1   => 'closed',
    2   => 'added',
    3   => 'changed',
    4   => 'nosummary',
    5   => 'nobudget',
    6   => 'noreport',
);
my %CURRENCY_FLAGS = (
    1   => 'custom',
);
my %CATEGORY_FLAGS = (
    0   => 'sub',
    1   => 'income',
    2   => 'custom',
    3   => 'budget',
    4   => 'forced',
);
my %TRANSACTION_FLAGS = (
    0   => 'oldvalid',
    1   => 'income',
    2   => 'auto',
    3   => 'added',
    4   => 'changed',
    5   => 'oldremind',
    6   => 'cheq2',
    7   => 'limit',
    8   => 'split',
);
my %TRANSACTION_STATUSES = (
    0   => 'none',
    1   => 'cleared',
    2   => 'reconciled',
    3   => 'remind',
    4   => 'void',
);
my %TRANSACTION_PAYMODES = (
    0   => 'none',
    1   => 'creditcard',
    2   => 'check',
    3   => 'cash',
    4   => 'transfer',
    5   => 'internaltransfer',
    6   => 'debitcard',
    7   => 'repeatpayment',
    8   => 'epayment',
    9   => 'deposit',
    10  => 'fee',
    11  => 'directdebit',
);

=method new

    $homebank = File::HomeBank->new(string => $str);
    $homebank = File::HomeBank->new(file => $filepath);

Construct a L<File::HomeBank>.

=cut

my %CACHE;

sub new {
    my $class = shift;
    my %args  = @_;

    my $self;

    if (my $filepath = $args{file}) {
        $self = parse_file($filepath);
        $self->{file} = $filepath;
    }
    elsif (my $str = $args{string}) {
        $self = parse_string($str);
    }
    else {
        _usage(q{File::HomeBank->new(string => $str)});
    }

    return bless $self, $class;
}

sub DESTROY {
    my $self = shift;
    my $in_global_destruction = shift;
    delete $CACHE{refaddr($self)} if !$in_global_destruction;
}

=attr file

Get the filepath (if parsed from a file).

=cut

sub file {
    shift->{file};
}

=method title

    $title = $homebank->title;

Get the title or owner property.

=cut

sub title {
    shift->{properties}{title};
}

=method base_currency

    $base_currency = $homebank->base_currency;

Get the key of the base currency.

=cut

sub base_currency {
    shift->{properties}{currency};
}

=method accounts

Get an arrayref of accounts.

=method categories

Get an arrayref of categories.

=method currencies

Get an arrayref of currencies.

=method payees

Get an arrayref of payees.

=method tags

Get an arrayref of tags.

=method transactions

Get an arrayref of transactions.

=cut

sub accounts     { shift->{accounts}     || [] }
sub categories   { shift->{categories}   || [] }
sub currencies   { shift->{currencies}   || [] }
sub payees       { shift->{payees}       || [] }
sub transactions { shift->{transactions} || [] }

sub tags {
    my $self = shift;

    my %tags;

    for my $transaction (@{$self->transactions}) {
        for my $tag (split(/\h+/, $transaction->{tags} || '')) {
            $tags{$tag} = 1;
        }
    }

    return [keys %tags];
}

=method find_account_by_key

    $account = $homebank->find_account_by_key($key);

Find a account with the given key.

=cut

sub find_account_by_key {
    my $self = shift;
    my $key  = shift or return;

    my $index = $CACHE{refaddr($self)}{account_by_key};
    if (!$index) {
        # build index
        for my $account (@{$self->accounts}) {
            $index->{$account->{key}} = $account;
        }

        $CACHE{refaddr($self)}{account_by_key} = $index;
    }

    return $index->{$key};
}

=method find_currency_by_key

    $currency = $homebank->find_currency_by_key($key);

Find a currency with the given key.

=cut

sub find_currency_by_key {
    my $self = shift;
    my $key  = shift or return;

    my $index = $CACHE{refaddr($self)}{currency_by_key};
    if (!$index) {
        # build index
        for my $currency (@{$self->currencies}) {
            $index->{$currency->{key}} = $currency;
        }

        $CACHE{refaddr($self)}{currency_by_key} = $index;
    }

    return $index->{$key};
}

=method find_category_by_key

    $category = $homebank->find_category_by_key($key);

Find a category with the given key.

=cut

sub find_category_by_key {
    my $self = shift;
    my $key  = shift or return;

    my $index = $CACHE{refaddr($self)}{category_by_key};
    if (!$index) {
        # build index
        for my $category (@{$self->categories}) {
            $index->{$category->{key}} = $category;
        }

        $CACHE{refaddr($self)}{category_by_key} = $index;
    }

    return $index->{$key};
}

=method find_payee_by_key

    $payee = $homebank->find_payee_by_key($key);

Find a payee with the given key.

=cut

sub find_payee_by_key {
    my $self = shift;
    my $key  = shift or return;

    my $index = $CACHE{refaddr($self)}{payee_by_key};
    if (!$index) {
        # build index
        for my $payee (@{$self->payees}) {
            $index->{$payee->{key}} = $payee;
        }

        $CACHE{refaddr($self)}{payee_by_key} = $index;
    }

    return $index->{$key};
}

=method find_transactions_by_transfer_key

    @transactions = $homebank->find_transactions_by_transfer_key($key);

Find all transactions that share the same transfer key.

=cut

sub find_transactions_by_transfer_key {
    my $self = shift;
    my $key  = shift or return;

    my $index = $CACHE{refaddr($self)}{transactions_by_transfer_key};
    if (!$index) {
        # build index
        for my $transaction (@{$self->transactions}) {
            my $xfkey = $transaction->{transfer_key} or next;
            push @{$index->{$xfkey} ||= []}, $transaction;
        }

        $CACHE{refaddr($self)}{transactions_by_transfer_key} = $index;
    }

    return @{$index->{$key} || []};
}

=method find_transaction_transfer_pair

    $other_transaction = $homebank->find_transaction_transfer_pair($transaction);

Given a transaction hashref, return its corresponding transaction if it is an internal transfer. If
the transaction is an internal transaction with a destination account but is orphaned (has no
matching transfer key), this also looks for another orphaned transaction in the destination account
that it can call its partner.

Returns undef or empty if no corresponding transaction is found.

=cut

sub find_transaction_transfer_pair {
    my $self = shift;
    my $transaction = shift;

    return if $transaction->{paymode} ne 'internaltransfer';

    my $transfer_key = $transaction->{transfer_key};

    my @matching = grep { refaddr($_) != refaddr($transaction) }
                   $self->find_transactions_by_transfer_key($transfer_key);
    warn "Found more than two transactions with the same transfer key.\n" if 1 < @matching;
    return $matching[0] if @matching;

    warn "Found internal transfer with no tranfer key.\n" if !defined $transfer_key;

    my $dst_account = $self->find_account_by_key($transaction->{dst_account});
    if (!$dst_account) {
        warn "Found internal transfer with no destination account.\n";
        return;
    }

    my @candidates;

    for my $t (@{$self->transactions}) {
        next if $t->{paymode} ne 'internaltransfer';
        next if $t->{account} != $transaction->{dst_account};
        next if $t->{dst_account} != $transaction->{account};
        next if $t->{amount} != -$transaction->{amount};

        my @matching = $self->find_transactions_by_transfer_key($t->{transfer_key});
        next if 1 < @matching;  # other transaction must also be orphaned

        push @candidates, $t;
    }

    my $transaction_day = _ymd_to_julian($transaction->{date});

    # sort the candidates so we can pick the nearest one by date
    my @ordered_candidates =
        map { $_->[1] }
        sort { $a->[0] <=> $b->[0] }
        map { [abs($transaction_day - _ymd_to_julian($_->{date})), $_] } @candidates;

    if (my $winner = $ordered_candidates[0]) {
        my $key1 = $transfer_key || '[no key]';
        my $key2 = $winner->{transfer_key} || '[no key]';
        warn "Paired orphaned internal transfer ${key1} and ${key2}.\n";
        return $winner;
    }
}

=method sorted_transactions

    $transations = $homebank->sorted_transactions;

Get an arrayref of transactions sorted by date (earliest first).

=cut

sub sorted_transactions {
    my $self = shift;

    my $sorted_transactions = $CACHE{refaddr($self)}{sorted_transactions};
    if (!$sorted_transactions) {
        $sorted_transactions = [sort { $a->{date} cmp $b->{date} } @{$self->transactions}];

        $CACHE{refaddr($self)}{sorted_transactions} = $sorted_transactions;
    }

    return $sorted_transactions;
}

=method full_category_name

    $category_name = $homebank->full_category_name($key);

Generate the full name for a category, taking category inheritance into consideration.

    Income
      Salary    <--

will become:

    "Income:Salary"

=cut

sub full_category_name {
    my $self = shift;
    my $key  = shift or return;

    my $cat = $self->find_category_by_key($key);

    my @categories = ($cat);

    while (my $parent_key = $cat->{parent}) {
        $cat = $self->find_category_by_key($parent_key);
        unshift @categories, $cat;
    }

    return join(':', map { $_->{name} } @categories);
}

=method format_amount

    $formatted_amount = $homebank->format_amount($amount);
    $formatted_amount = $homebank->format_amount($amount, $currency);

Formats an amount in either the base currency (for the whole file) or in the given currency.
Currency can be a key or the actualy currency structure.

=cut

sub format_amount {
    my $self     = shift;
    my $amount   = shift;
    my $currency = shift || $self->base_currency;

    $currency = $self->find_currency_by_key($currency) if !ref($currency);
    _croak 'Must provide a valid currency' if !$currency;

    my $format = "\% .$currency->{frac}f";
    my ($whole, $fraction) = split(/\./, sprintf($format, $amount));

    my $num = join($currency->{dchar}, commify($whole, $currency->{gchar}), $fraction);

    $num = $currency->{syprf} ? "$currency->{symbol} $num" : "$num $currency->{symbol}";

    return $num;
}

=func parse_file

    $homebank_data = parse_file($filepath);

Read and parse a HomeBank .xhb file from a filesystem.

=cut

sub parse_file {
    my $filepath = shift or _usage(q{parse_file($filepath)});

    open(my $fh, '<', $filepath) or die "open failed: $!";
    my $str_in = do { local $/; <$fh> };

    return parse_string($str_in);
}

=func parse_string

    $homebank_data = parse_string($str);

Parse a HomeBank file from a string.

=cut

sub parse_string {
    my $str = shift or die _usage(q{parse_string($str)});

    my %properties;
    my @accounts;
    my @payees;
    my @categories;
    my @currencies;
    my @transactions;

    my $xml_parser = XML::Parser::Lite->new(
        Handlers => {
            Start   => sub {
                shift;
                my $node = shift;
                my %attr = @_;
                if ($node eq 'properties') {
                    $attr{currency} = delete $attr{curr} if $attr{curr};
                    %properties = %attr;
                }
                elsif ($node eq 'account') {
                    $attr{type}             = $ACCOUNT_TYPES{$attr{type} || ''} || 'unknown';
                    $attr{bank_name}        = delete $attr{bankname} if $attr{bankname};
                    $attr{currency}         = delete $attr{curr}     if $attr{curr};
                    $attr{display_position} = delete $attr{pos}      if $attr{pos};

                    my $flags = delete $attr{flags} || 0;
                    while (my ($shift, $name) = each %ACCOUNT_FLAGS) {
                        $attr{flags}{$name} = $flags & (1 << $shift) ? 1 : 0;
                    }

                    push @accounts, \%attr;
                }
                elsif ($node eq 'pay') {    # payee
                    push @payees, \%attr;
                }
                elsif ($node eq 'cur') {    # currency
                    $attr{symbol} = delete $attr{symb} if $attr{symb};

                    my $flags = delete $attr{flags} || 0;
                    while (my ($shift, $name) = each %CURRENCY_FLAGS) {
                        $attr{flags}{$name} = $flags & (1 << $shift) ? 1 : 0;
                    }

                    push @currencies, \%attr;
                }
                elsif ($node eq 'cat') {    # category
                    my $flags = delete $attr{flags} || 0;
                    while (my ($shift, $name) = each %CATEGORY_FLAGS) {
                        $attr{flags}{$name} = $flags & (1 << $shift) ? 1 : 0;
                    }

                    push @categories, \%attr;
                }
                elsif ($node eq 'ope') {    # transaction
                    $attr{paymode} = $TRANSACTION_PAYMODES{$attr{paymode} || ''} || 'unknown';
                    $attr{status}  = $TRANSACTION_STATUSES{delete $attr{st}} || 'unknown';

                    $attr{transfer_key}   = delete $attr{kxfer} if $attr{kxfer};
                    $attr{split_amount}   = delete $attr{samt}  if $attr{samt};
                    $attr{split_memo}     = delete $attr{smem}  if $attr{smem};
                    $attr{split_category} = delete $attr{scat}  if $attr{scat};

                    $attr{date} = _rdn_to_ymd($attr{date}) if $attr{date};

                    my $flags = delete $attr{flags} || 0;
                    while (my ($shift, $name) = each %TRANSACTION_FLAGS) {
                        $attr{flags}{$name} = $flags & (1 << $shift) ? 1 : 0;
                    }

                    push @transactions, \%attr;
                }
            },
        },
    );
    $xml_parser->parse($str);

    return {
        properties      => \%properties,
        accounts        => \@accounts,
        payees          => \@payees,
        categories      => \@categories,
        currencies      => \@currencies,
        transactions    => \@transactions,
    };
}

sub _rdn_to_unix_epoch {
    my $rdn = shift;
    my $jan01_1970 = 719163;
    return ($rdn - $jan01_1970) * 86400;
}

sub _rdn_to_ymd {
    my $rdn = shift;
    my $epoch = _rdn_to_unix_epoch($rdn);
    my $time = gmtime($epoch);
    return $time->ymd;
};

sub _ymd_to_julian {
    my $ymd = shift;
    my $t = Time::Piece->strptime($ymd, '%Y-%m-%d');
    return $t->julian_day;
}

1;
