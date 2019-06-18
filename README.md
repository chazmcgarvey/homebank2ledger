# NAME

homebank2ledger - A tool to convert HomeBank files to Ledger format

# VERSION

version 0.004

# SYNOPSIS

    homebank2ledger --input FILEPATH [--output FILEPATH] [--format FORMAT]
                    [--version|--help|--manual] [--account-width NUM]
                    [--accounts|--no-accounts] [--payees|--no-payees]
                    [--tags|--no-tags] [--commodities|--no-commodities]
                    [--opening-date DATE]
                    [--rename-account STR]... [--exclude-account STR]...

# DESCRIPTION

`homebank2ledger` converts [HomeBank](http://homebank.free.fr/) files to a format usable by
[Ledger](https://www.ledger-cli.org/). It can also convert directly to the similar
[Beancount](http://furius.ca/beancount/) format.

This software is **EXPERIMENTAL**, in early development. Its interface may change without notice.

I wrote `homebank2ledger` because I have been maintaining my own personal finances using HomeBank
(which is awesome) and I wanted to investigate using plain text accounting programs. It works well
enough for my data, but you may be using HomeBank features that I don't so there may be cases this
doesn't handle well or at all. Feel free to file a bug report. This script does NOT try to modify
the original HomeBank files it converts from, so there won't be any crazy data loss bugs... but no
warranty.

## Features

- Converts HomeBank accounts and categories into a typical set of double-entry accounts.
- Retains HomeBank metadata, including payees and tags.
- Offers some customization of the output ledger, like account renaming.

This program is feature-complete in my opinion (well, almost -- see ["CAVEATS"](#caveats)), but if there is
anything you think it could do to be even better, feedback is welcome; just file a bug report. Or
fork the code and have fun!

## Use cases

You can migrate the data you have in HomeBank so you can start maintaining your accounts in Ledger
(or Beancount).

Or if you don't plan to switch completely off of HomeBank, you can continue to maintain your
accounts in HomeBank and use this script to also take advantage of the reports Ledger offers.

# OPTIONS

## --version

Print the version and exit.

Alias: `-V`

## --help

Print help/usage info and exit.

Alias: `-h`, `-?`

## --manual

Print the full manual and exit.

Alias: `--man`

## --input FILEPATH

Specify the path to the HomeBank file to read (must already exist).

Alias: `--file`, `-i`

## --output FILEPATH

Specify the path to the Ledger file to write (may not exist yet). If not provided, the formatted
ledger will be printed on `STDOUT`.

Alias: `-o`

## --format STR

Specify the output file format. If provided, must be one of:

- ledger
- beancount

## --account-width NUM

Specify the number of characters to reserve for the account column in transactions. Adjusting this
can provide prettier formatting of the output.

Defaults to 40.

## --accounts

Enables account declarations.

Defaults to enabled; use `--no-accounts` to disable.

## --payees

Enables payee declarations.

Defaults to enabled; use `--no-payees` to disable.

## --tags

Enables tag declarations.

Defaults to enabled; use `--no-tags` to disable.

## --commodities

Enables commodity declarations.

Defaults to enabled; use `--no-commodities` to disable.

## --opening-date DATE

Specify the opening date for the "opening balances" transaction. This transaction is created (if
needed) to support HomeBank's ability to configure accounts with opening balances.

Date must be in the form "YYYY-MM-DD". Defaults to the date of the first transaction.

## --rename-account STR

Specifies a mapping for renaming accounts in the output. By default `homebank2ledger` tries to come
up with sensible account names (based on your HomeBank accounts and categories) that fit into five
root accounts:

- Assets
- Liabilities
- Equity
- Income
- Expenses

The value of the argument must be of the form "REGEXP=REPLACEMENT". See ["EXAMPLES"](#examples).

Can be repeated to rename multiple accounts.

## --exclude-account STR

Specifies an account that will not be included in the output. All transactions related to this
account will be skipped.

Can be repeated to exclude multiple accounts.

# EXAMPLES

## Basic usage

    # Convert homebank.xhb to a Ledger-compatible file:
    homebank2ledger path/to/homebank.xhb -o ledger.dat

    # Run the Ledger balance report:
    ledger -f ledger.dat balance

You can also combine this into one command:

    homebank2ledger path/to/homebank.xhb | ledger -f - balance

## Account renaming

With the ["--rename-account STR"](#rename-account-str) argument, you have some control over the resulting account
structure. This may be useful in cases where the organization imposed (or encouraged) by HomeBank
doesn't necessarily line up with an ideal double-entry structure.

    homebank2ledger path/to/homebank.xhb -o ledger.dat \
        --rename-account '^Assets:Credit Union Savings$=Assets:Bank:Credit Union:Savings' \
        --rename-account '^Assets:Credit Union Checking$=Assets:Bank:Credit Union:Checking'

Multiple accounts can be renamed at the same time because the first part of the mapping is a regular
expression. The above example could be written like this:

    homebank2ledger path/to/homebank.xhb -o ledger.dat \
        --rename-account '^Assets:Credit Union =Assets:Bank:Credit Union:'

You can also merge accounts by simple renaming multiple accounts to the same name:

    homebank2ledger path/to/homebank.xhb -o ledger.dat \
        --rename-account '^Liabilities:Chase VISA$=Liabilities:All Credit Cards' \
        --rename-account '^Liabilities:Amex$=Liabilities:All Credit Cards'

If you need to do anything more complicated, of course you can edit the output after converting;
it's just plain text.

## Beancount

    # Convert homebank.xhb to a Beancount-compatible file:
    homebank2ledger path/to/homebank.xhb -f beancount -o ledger.beancount

    # Run the balances report:
    bean-report ledger.beancount balances

# CAVEATS

- I didn't intend to make this a releasable robust product, so it's lacking tests.
- Budgets and scheduled transactions are not (yet) converted.
- There are some minor formatting tweaks I will make (e.g. consolidate transaction tags and payees)

# BUGS

Please report any bugs or feature requests on the bugtracker website
[https://github.com/chazmcgarvey/homebank2ledger/issues](https://github.com/chazmcgarvey/homebank2ledger/issues)

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

# AUTHOR

Charles McGarvey <chazmcgarvey@brokenzipper.com>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2019 by Charles McGarvey.

This is free software, licensed under:

    The MIT (X11) License
