 
package OpenXPKI::Server::Workflow::Activity::SmartCard::ApplyCSRPolicy;

use strict;
use English;
use base qw( OpenXPKI::Server::Workflow::Activity );

use OpenXPKI::Server::Context qw( CTX );
use OpenXPKI::Exception;
use OpenXPKI::Debug;
use OpenXPKI::Serialization::Simple;

use Data::Dumper;
use Template;

sub execute {
    ##! 1: 'start'
    my $self     = shift;
    my $workflow = shift;
    my $context  = $workflow->context();
    my $serializer = OpenXPKI::Serialization::Simple->new();

    my $config = CTX('config');
    
    $context->param( policy_input_required => '');
    
    # The certifiacte type of the current loop is in csr_cert_type
    my $cert_type = $context->param('csr_cert_type');
    ##! 8: ' Prepare CSR for cert type ' . $cert_type 
        
    # Get profile from certificate type
    my $cert_profile = $config->get( [ 'smartcard.policy.certs.type', $cert_type, 'allowed_profiles.0' ] );
    my $cert_role = $config->get( [ 'smartcard.policy.certs.type', $cert_type, 'role' ] ) || 'User';
    ##! 8: ' Prepare CSR for profile '. $cert_profile .' with role '. $cert_role 

    # cert_issuance_data is an array of hashes, one entry per certificate
    
    my $cert_issuance_data_context = OpenXPKI::Server::Workflow::WFObject::WFArray->new(
        { workflow => $workflow , context_key => 'cert_issuance_data' } );
    
       
    # prepare hashref for Template Toolkit based on userinfo context values
    my $userinfo;
    foreach my $param (keys %{ $context->param() }) {
        if ($param =~ s{ \A userinfo_ }{}xms) {
            ##! 64: 'adding param ' . $param . ' to userinfo, value: ' . $context->param('userinfo_' . $param)            
            $userinfo->{$param} = $context->param('userinfo_' . $param);            
            # Some entries are arrays
            if ($userinfo->{$param} =~ /\A ARRAY/xms) {            
                $userinfo->{$param} = $serializer->deserialize($userinfo->{$param});
            }
        }
    }
    
    my $cert_subject_template = $config->get( [ 'profile', $cert_profile, 'subject' ] );
    my $sans_template = $config->get( [ 'profile', $cert_profile, 'subject_alternative_names' ] ) || '';
                          
    #############################################################
    # Processing of UPN Mappings for Windows Login certificates
    #
    # check with policy how many logins are allowed (max_login)
    # if number of logins exceeds limit, present them to the frontend
    # if number of logins matches limit, autoselect them and proceed
    # Match logins to UPNs using connector (assumed to be unique)         
    
    my $max_login = $config->get( [ 'smartcard.policy.certs.type', $cert_type, 'max_login' ] ) || 0;
    if ($max_login > 0) {

        # Available Logins are in the user info hash
        my $allowed_logins = $userinfo->{loginids};        
        my @use_logins;        
        
        ##! 8: ' Certificate needs '. $max_login . ' Login/UPNs. Found: '  . scalar @{$allowed_logins}
        ##! 16: ' Allowed Logins found ' .  join("\n", @{$allowed_logins})
        
        # Check if frontend passed a selection        
        if ($context->param( 'login_ids' )) {
            my $login_ids_wf = OpenXPKI::Server::Workflow::WFObject::WFArray->new(
            {
                workflow    => $workflow,
                context_key => 'login_ids',
            } );                       
            if ($login_ids_wf->count() > $max_login) {
                ##! 16: ' Frontend passed too many login ids '
                $context->param( policy_request_login_ids => $max_login);
                OpenXPKI::Exception->throw(
                    message => 'I18N_OPENXPKI_SERVER_WORKFLOW_ACTIVITY_SMARTCARD_APPLYCSRPOLICY_TOO_MANY_LOGINIDS',
                    params => {
                        'LOGIN_ID' => $context->param( 'login_id' ),                        
                    },
                );
            }
            
            # Validation - check if the passed logins are allowed
            @use_logins = @{$login_ids_wf->values()};
            ##! 16: ' Frontend passed login ids : ' . Dumper ( @use_logins )
            foreach my $login (@use_logins) {
                ##! 32 ' Check login against list of allowed ones ' . $login
                if (!grep ($login, @{$allowed_logins})) {
                    OpenXPKI::Exception->throw(
                        message => 'I18N_OPENXPKI_SERVER_WORKFLOW_ACTIVITY_SMARTCARD_APPLYCSRPOLICY_LOGINID_NOT_ALLOWED',
                        params => {
                            'LOGIN_ID' => $login,
                            'ALLOWED_IDS' => join (', ', @{$allowed_logins})                            
                        },
                    );  
                }
            }
            $context->param( 'login_ids' );
        } elsif (scalar @{$allowed_logins} > $max_login) {        
            # More then allowed
            ##! 16: ' Too many logins found - ask frontend '        
            # Present the available Logins and the max_login count via the context
            # Clean context first
            $context->param( policy_login_ids => );
            # Create array
            my $policy_login_ids_wf = OpenXPKI::Server::Workflow::WFObject::WFArray->new(
            {
                workflow    => $workflow,
                context_key => 'policy_login_ids',
            } );
            $policy_login_ids_wf->push(@{$allowed_logins});
            $context->param( policy_max_login_ids => $max_login);            
            $context->param( policy_input_required => 'login_ids');
            return; # FIXME - is this safe?
        } else {
            @use_logins = @{$allowed_logins};
        }

        ##! 32: 'Will use these logins ' . Dumper( @use_logins )
        
        foreach my $login (@use_logins) {
            # Fetch the UPN for each login
            ##! 32: ' Search UPN for ' . $login
 
            # Strip domain and user
            my ($domain, $user) = split(/\\/, $login);	
            $domain = uc($domain);
 
            # If the login has domain/user format, try if there is a special 
            # query point for that domain
         
            my $upn;
            if ($user && $config->get_meta( [ 'smartcard.upninfo', $domain ] )) {
                $upn = $config->get(['smartcard.upninfo', $domain, $user ]);
                ##! 16: ' Direct domain lookup ' . Dumper( $upn )
            } else {
                my $res = $config->walkQueryPoints('smartcard.upninfo', $login );
                $upn = $res->{VALUE};
                ##! 16: ' Connector walk ' . Dumper( $res )
            }     

            if (!$upn) {
                OpenXPKI::Exception->throw(
                    message => 'I18N_OPENXPKI_SERVER_WORKFLOW_ACTIVITY_SMARTCARD_APPLYCSRPOLICY_NO_UPN_FOUND',
                    params => {
                    'LOGIN_ID' => $login,
                    'PREFIX'   => 'smartcard.upninfo',
                    },
                );
            }
            push @{$userinfo->{upn}}, $upn;
        }
        
        ##! 16: ' UPNs found ' . Dumper( @{$userinfo->{upn}} )
        

        # Add the chosel logins to the userinfo structure                    
        $userinfo->{chosen_logins} = \@use_logins;
    } # End of Login / UPN processing
                          
                          
    ##! 32: ' Userinfo as passed to TT : ' . Dumper ( $userinfo )
                          
    # process subject using TT
    
    my $tt = Template->new();
    my $cert_subject = '';
    $tt->process(\$cert_subject_template, $userinfo, \$cert_subject);
    ##! 16: 'cert_subject: ' . $cert_subject

    # process subject alternative names using TT    
    my $cert_subj_alt_names = '';
    $tt->process(\$sans_template, $userinfo, \$cert_subj_alt_names);
    ##! 16: 'cert_subj_alt_names: ' . $cert_subj_alt_names

    my @sans = split(/,/, $cert_subj_alt_names);
    foreach my $entry (@sans) {
        my @tmp_array = split(/=/, $entry);
        $entry = \@tmp_array;
    }
    ##! 16: '@sans: ' . Dumper(\@sans)
 
 
    # Mark escrow certificates
    my $escrow_key_handle = ''; 
    if ($config->get( [ 'smartcard.policy.certs.type', $cert_type, 'escrow_key' ] ) && 
        $context->param('temp_key_handle')) {
        $escrow_key_handle =  $context->param('temp_key_handle');
    }
    # Unset 
    $context->param({ temp_key_handle => undef });
        
    my $cert_issuance_hash_ref = {
        'escrow_key_handle'     => $escrow_key_handle,
        'pkcs10'                => $context->param('pkcs10'),
        'csr_type'              => 'pkcs10',
        'cert_profile'          => $cert_profile,
        'cert_role'             => $cert_role,
        'cert_subject'          => $cert_subject,
        'cert_subject_alt_name' => \@sans,
    };
    ##! 16: 'cert_iss_hash_ref: ' . Dumper($cert_issuance_hash_ref)
    $cert_issuance_data_context->push( $cert_issuance_hash_ref );
    
    ##! 4: 'end'
    return;
}

1;
__END__

=head1 Name

OpenXPKI::Server::Workflow::Activity::SmartCard::ApplyCSRPolicy

=head1 Description

This class takes the CSR from the client and sets up an array of
hashrefs in the context (cert_issuance_data) which contains all
information needed to persist them in the database and then fork
certificate issuance workflows.

