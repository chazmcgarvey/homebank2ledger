package App::HomeBank2Ledger;
# ABSTRACT: A tool to convert HomeBank files to Ledger format

=head1 SYNOPSIS

    App::HomeBank2Ledger->main(@args);

=head1 DESCRIPTION

This module is part of the L<homebank2ledger> script.

=cut

# TODO - add posting memo
# TODO - transaction description ("narration" in beancount)
# TODO - payees
# TODO - budget/scheduled
# TODO - consolidate tags on transaction
# TODO - consolidate payees on transaction

use warnings FATAL => 'all';    # temp fatal all
use strict;

use App::HomeBank2Ledger::Formatter;
use App::HomeBank2Ledger::Ledger;
use File::HomeBank;
use Getopt::Long 2.38 qw(GetOptionsFromArray);
use Pod::Usage;

our $VERSION = '9999.999'; # VERSION

my %ACCOUNT_TYPES = (   # map HomeBank account types to Ledger accounts
    bank        => 'Assets:Bank',
    cash        => 'Assets:Cash',
    asset       => 'Assets:Fixed Assets',
    creditcard  => 'Liabilities:Credit Card',
    liability   => 'Liabilities',
    stock       => 'Assets:Stock',
    mutualfund  => 'Assets:Mutual Fund',
    income      => 'Income',
    expense     => 'Expenses',
    equity      => 'Equity',
);
my %STATUS_SYMBOLS = (
    cleared     => 'cleared',
    reconciled  => 'cleared',
    remind      => 'pending',
);
my $UNKNOWN_ACCOUNT = 'Assets:Unknown';
my $OPENING_BALANCES_ACCOUNT = 'Equity:Opening Balances';

=method main

    App::HomeBank2Ledger->main(@args);

Run the script and exit; does not return.

=cut

sub main {
    my $class = shift;
    my $self  = bless {}, $class;

    my $opts = $self->parse_args(@_);

    if ($opts->{version}) {
        print "homebank2ledger ${VERSION}\n";
        exit 0;
    }
    if ($opts->{help}) {
        pod2usage(-exitval => 0, -verbose => 99, -sections => [qw(NAME SYNOPSIS OPTIONS)]);
    }
    if ($opts->{manual}) {
        pod2usage(-exitval => 0, -verbose => 2);
    }

    my $homebank = File::HomeBank->new(file => $opts->{input});

    my $formatter = eval { $self->formatter($homebank, $opts) };
    if (my $err = $@) {
        if ($err =~ /^Invalid formatter/) {
            print STDERR "Invalid format: $opts->{format}\n";
            exit 2;
        }
        die $err;
    }

    my $ledger = $self->convert_homebank_to_ledger($homebank, $opts);

    $self->print_to_file($formatter->format($ledger), $opts->{output});

    exit 0;
}

=method formatter

    $formatter = $app->formatter($homebank, $opts);

Generate a L<App::HomeBank2Ledger::Formatter>.

=cut

sub formatter {
    my $self     = shift;
    my $homebank = shift;
    my $opts     = shift || {};

    return App::HomeBank2Ledger::Formatter->new(
        type            => $opts->{format},
        account_width   => $opts->{account_width},
        name            => $homebank->title,
        file            => $homebank->file,
    );
}

=method convert_homebank_to_ledger

    my $ledger = $app->convert_homebank_to_ledger($homebank, $opts);

Converts a L<File::HomeBank> to a L<App::HomeBank2Ledger::Ledger>.

=cut

sub convert_homebank_to_ledger {
    my $self     = shift;
    my $homebank = shift;
    my $opts     = shift || {};

    my $ledger = App::HomeBank2Ledger::Ledger->new;

    my $transactions    = $homebank->sorted_transactions;
    my $accounts        = $homebank->accounts;
    my $categories      = $homebank->categories;

    # determine full Ledger account names
    for my $account (@$accounts) {
        my $type = $ACCOUNT_TYPES{$account->{type}} || $UNKNOWN_ACCOUNT;
        $account->{ledger_name} = "${type}:$account->{name}";
    }
    for my $category (@$categories) {
        my $type = $category->{flags}{income} ? 'Income' : 'Expenses';
        my $full_name = $homebank->full_category_name($category->{key});
        $category->{ledger_name} = "${type}:${full_name}";
    }

    # handle renaming and marking excluded accounts
    for my $item (@$accounts, @$categories) {
        while (my ($re, $replacement) = each %{$opts->{rename_accounts}}) {
            $item->{ledger_name} =~ s/$re/$replacement/;
        }
        for my $re (@{$opts->{exclude_accounts}}) {
            $item->{excluded} = 1 if $item->{ledger_name} =~ /$re/;
        }
    }

    my $has_initial_balance = grep { $_->{initial} && !$_->{excluded} } @$accounts;

    if ($opts->{accounts}) {
        my @accounts = map { $_->{ledger_name} } grep { !$_->{excluded} } @$accounts, @$categories;

        push @accounts, $opts->{default_account};
        push @accounts, $OPENING_BALANCES_ACCOUNT if $has_initial_balance;

        $ledger->add_accounts(@accounts);
    }

    if ($opts->{payees}) {
        my $payees = $homebank->payees;
        my @payees = map { $_->{name} } @$payees;

        $ledger->add_payees(@payees);
    }

    if ($opts->{tags}) {
        my $tags = $homebank->tags;

        $ledger->add_tags(@$tags);
    }

    my %commodities;

    for my $currency (@{$homebank->currencies}) {
        my $commodity = {
            symbol  => $currency->{symbol},
            format  => $homebank->format_amount(1_000, $currency),
            iso     => $currency->{iso},
            name    => $currency->{name},
        };
        $commodities{$currency->{key}} = {
            %$commodity,
            syprf   => $currency->{syprf},
            dchar   => $currency->{dchar},
            gchar   => $currency->{gchar},
            frac    => $currency->{frac},
        };

        $ledger->add_commodities($commodity) if $opts->{commodities};
    }

    if ($has_initial_balance) {
        # transactions are sorted, so the first transaction is the earliest
        my $first_date = $opts->{opening_date} || $transactions->[0]{date};
        if ($first_date !~ /^\d{4}-\d{2}-\d{2}$/) {
            die "Opening date must be in the form YYYY-MM-DD.\n";
        }

        my @postings;

        for my $account (@$accounts) {
            next if !$account->{initial} || $account->{excluded};

            push @postings, {
                account     => $account->{ledger_name},
                amount      => $account->{initial},
                commodity   => $commodities{$account->{currency}},
            };
        }

        push @postings, {
            account => $OPENING_BALANCES_ACCOUNT,
        };

        $ledger->add_transactions({
            date        => $first_date,
            payee       => 'Opening Balance',
            status      => 'cleared',
            postings    => \@postings,
        });
    }

    my %seen;

    TRANSACTION:
    for my $transaction (@$transactions) {
        next if $seen{$transaction->{transfer_key} || ''};

        my $account = $homebank->find_account_by_key($transaction->{account});
        my $amount  = $transaction->{amount};
        my $status  = $STATUS_SYMBOLS{$transaction->{status} || ''} || '';
        my $paymode = $transaction->{paymode} || ''; # internaltransfer
        my $memo    = $transaction->{wording} || '';
        my $payee   = $homebank->find_payee_by_key($transaction->{payee});
        my $tags    = _split_tags($transaction->{tags});

        my @postings;

        push @postings, {
            account     => $account->{ledger_name},
            amount      => $amount,
            commodity   => $commodities{$account->{currency}},
            payee       => $payee->{name},
            memo        => $memo,
            status      => $status,
            tags        => $tags,
        };

        if ($paymode eq 'internaltransfer') {
            my $paired_transaction = $homebank->find_transaction_transfer_pair($transaction);

            my $dst_account = $homebank->find_account_by_key($transaction->{dst_account});
            if (!$dst_account) {
                if ($paired_transaction) {
                    $dst_account = $homebank->find_account_by_key($paired_transaction->{account});
                }
                if (!$dst_account) {
                    warn "Skipping internal transfer transaction with no destination account.\n";
                    next TRANSACTION;
                }
            }

            $seen{$transaction->{transfer_key}}++        if $transaction->{transfer_key};
            $seen{$paired_transaction->{transfer_key}}++ if $paired_transaction->{transfer_key};

            my $paired_payee = $homebank->find_payee_by_key($paired_transaction->{payee});

            push @postings, {
                account     => $dst_account->{ledger_name},
                amount      => $paired_transaction->{amount} || -$transaction->{amount},
                commodity   => $commodities{$dst_account->{currency}},
                payee       => $paired_payee->{name},
                memo        => $paired_transaction->{wording} || '',
                status      => $STATUS_SYMBOLS{$paired_transaction->{status} || ''} || $status,
                tags        => _split_tags($paired_transaction->{tags}),
            };
        }
        elsif ($transaction->{flags}{split}) {
            my @amounts     = split(/\|\|/, $transaction->{split_amount}   || '');
            my @memos       = split(/\|\|/, $transaction->{split_memo}     || '');
            my @categories  = split(/\|\|/, $transaction->{split_category} || '');

            for (my $i = 0; $amounts[$i]; ++$i) {
                my $amount        = -$amounts[$i];
                my $category      = $homebank->find_category_by_key($categories[$i]);
                my $memo          = $memos[$i] || '';
                my $other_account = $category ? $category->{ledger_name} : $opts->{default_account};

                push @postings, {
                    account     => $other_account,
                    commodity   => $commodities{$account->{currency}},
                    amount      => $amount,
                    payee       => $payee->{name},
                    memo        => $memo,
                    status      => $status,
                    tags        => $tags,
                };
            }
        }
        else {  # with or without category
            my $category      = $homebank->find_category_by_key($transaction->{category});
            my $other_account = $category ? $category->{ledger_name} : $opts->{default_account};
            push @postings, {
                account     => $other_account,
                commodity   => $commodities{$account->{currency}},
                amount      => -$transaction->{amount},
                payee       => $payee->{name},
                memo        => '',  # TODO
                status      => $status,
                tags        => $tags,
            };
        }

        # skip excluded accounts
        for my $posting (@postings) {
            for my $re (@{$opts->{exclude_accounts}}) {
                next TRANSACTION if $posting->{account} =~ /$re/;
            }
        }

        $ledger->add_transactions({
            date        => $transaction->{date},
            payee       => 'Payee TODO',
            postings    => \@postings,
        });
    }

    return $ledger;
}

=method print_to_file

    $app->print_to_file($str);
    $app->print_to_file($str, $filepath);

Print a string to a file (or STDOUT).

=cut

sub print_to_file {
    my $self     = shift;
    my $str      = shift;
    my $filepath = shift;

    my $out_fh = \*STDOUT;
    if ($filepath) {
        open($out_fh, '>', $filepath) or die "open failed: $!";
    }
    print $out_fh $str;
}

=method parse_args

    $opts = $app->parse_args(@args);

Parse command-line arguments.

=cut

sub parse_args {
    my $self = shift;
    my @args = @_;

    my %opts = (
        version             => 0,
        help                => 0,
        manual              => 0,
        input               => undef,
        output              => undef,
        format              => 'ledger',
        account_width       => 40,
        accounts            => 1,
        payees              => 1,
        tags                => 1,
        commodities         => 1,
        opening_date        => '',
        default_account     => 'Expenses:No Category',
        rename_accounts     => {},
        exclude_accounts    => [],
    );

    GetOptionsFromArray(\@args,
        'version|V'             => \$opts{version},
        'help|h|?'              => \$opts{help},
        'manual|man'            => \$opts{manual},
        'input|file|i=s'        => \$opts{input},
        'output|o=s'            => \$opts{output},
        'format|f=s'            => \$opts{format},
        'account-width=i'       => \$opts{account_width},
        'accounts!'             => \$opts{accounts},
        'payees!'               => \$opts{payees},
        'tags!'                 => \$opts{tags},
        'commodities!'          => \$opts{commodities},
        'opening-date=s'        => \$opts{opening_date},
        'default-account=s'     => \$opts{default_account},
        'rename-account|r=s'    => \%{$opts{rename_accounts}},
        'exclude-account|x=s'   => \@{$opts{exclude_accounts}},
    ) or pod2usage(-exitval => 1, -verbose => 99, -sections => [qw(SYNOPSIS OPTIONS)]);

    $opts{input} = shift @args if !$opts{input};
    if (!$opts{input}) {
        print STDERR "Input file is required.\n";
        exit(1);
    }

    return \%opts;
}

sub _split_tags {
    my $tags = shift;
    return [split(/\h+/, $tags || '')];
}

1;