#######################################################
###                                                 ###
###   Preserv2/EPrints FormatsRisks Configuration   ###
###                                                 ###
#######################################################
###                                                 ###
###     Developed by David Tarrant and Tim Brody    ###
###                                                 ###
###          Released under the GPL Licence         ###
###           (c) University of Southampton         ###
###                                                 ###
###        Install in the following location:       ###
###      eprints/archives/archive_name/cfg/cfg.d/   ###
###                                                 ###
#######################################################

# The location of Java
#$c->{"executables"}->{"java"} = 'java';

# Maximum classification age in seconds
# Any classifications that are older than this will be updated
# To disable classification updates set max_age to 0

#$c->{pronom}->{max_age} = 30; # 30 seconds
$c->{pronom}->{max_age} = 30 * 86400; # 30 days

# High risk score boundary. Anything returning a risk score less than or equal to this will be classified as high risk.
# Risk scores go from 0 - 3000;
$c->{"high_risk_boundary"} = 1000;

# Medium risk score boundary. Anything returning a risk score less than or equal to this and greater than the high risk boundary will be classified as medium risk.
$c->{"medium_risk_boundary"} = 2000;

# Option to enable preservation plans to be executed on your repository by EPrints, this is off as there is some error handling missing.
$c->{"enable_preservation_actions"} = 0;

# Option to enable interface buttons to manually start classification scans, normally this process would just be controlled by a cron job.
$c->{"allow_droid_classification_control"} = 1;

# Option to use unstable version of PRONOM registry or proxy. This is mainly used in pre-release testing, leave as 0 to use actual pronom release.
$c->{"pronom_unstable"} = 0;
