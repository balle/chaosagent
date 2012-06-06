#!/bin/bash

echo "Installing required Perl modules from CPAN"
echo "If you're ask to configure CPAN manually say No"
echo "Otherwise always say Yes"
echo "Here we go..."

cpan Yahoo::Search
cpan Weather::Cached
cpan XML::Simple
cpan XML::RSS
cpan XML::RSS::Feed
