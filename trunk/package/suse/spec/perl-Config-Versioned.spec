%{!?perl_vendorlib: %define perl_vendorlib %(eval "`%{__perl} -V:installvendorlib`"; echo $installvendorlib)}

Name:           perl-Config-Versioned
Version:        0.7
Release:        1%{?dist}
Summary:        Simple, versioned access to configuration data
License:        GPL+ or Artistic
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/Config-Versioned/
Source0:        http://www.cpan.org/authors/id/M/MR/MRSCOTTY/Config-Versioned-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
# Config::Any -> Config-Any
BuildRequires:  perl(Config::Any)
# Config::Merge -> Config-Merge
BuildRequires:  perl(Config::Merge)
# Config::Std -> Config-Std
BuildRequires:  perl(Config::Std)
# DateTime -> DateTime
BuildRequires:  perl(DateTime)
# ExtUtils::MakeMaker -> ExtUtils-MakeMaker
BuildRequires:  perl(ExtUtils::MakeMaker)
# Git::PurePerl -> Git-PurePerl
BuildRequires:  perl(Git::PurePerl)
# Path::Class -> Path-Class
BuildRequires:  perl(Path::Class)
# Test::More -> Test-Simple
BuildRequires:  perl(Test::More)
# YAML::XS -> YAML-LibYAML
BuildRequires:  perl(YAML::XS)
Requires:       perl(Config::Any)
Requires:       perl(Config::Merge)
Requires:       perl(Config::Std)
Requires:       perl(Git::PurePerl)
Requires:       perl(YAML::XS)

%description
Config::Versioned allows an application to access configuration parameters
not only by parameter name, but also by version number. This allows for
the configuration subsystem to store previous versions of the
configuration parameters. When requesting the value for a specific
attribute, the programmer specifies whether to fetch the most recent value
or a previous value.

%prep
%setup -q -n Config-Versioned-%{version}

rm -f pm_to_blib

%build
%{__perl} Makefile.PL INSTALL_BASE=/usr/local INSTALLDIRS=vendor
make %{?_smp_mflags}

%install
rm -rf $RPM_BUILD_ROOT

make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT

find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} \;
find $RPM_BUILD_ROOT -depth -type d -exec rmdir {} 2>/dev/null \;

%{_fixperms} $RPM_BUILD_ROOT/*

perldoc -t perlgpl > COPYING
perldoc -t perlartistic > Artistic

%check || :
make test

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc build.mkd Changes commands README COPYING Artistic
/usr/local/*

%changelog
* Fri Apr 27 2012 <Scott T. Hardin> 0.6-1
- Specfile autogenerated by cpanspec 1.78.
