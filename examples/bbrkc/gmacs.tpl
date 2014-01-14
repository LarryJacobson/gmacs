// =========================================================================================================                                   
//   Gmacs: Generalized Modelling for Alaskan Crab Stocks.
//
//   Authors: Athol Whitten, University of Washington   
//            Jim Ianelli, NOAA Alaskan Fisheries Science Centre
//
//   Info: https://github.com/awhitten/gmacs or write to whittena@uw.edu
//   Copyright (c) 2014. All rights reserved.
//
//   Acknowledgement: The format of this code, and many of the details,
//   were adapted from code developed for the NPFMC by Andre Punt (2012), 
//   and on the 'LSMR' model by Steven Martell (2011).
//
//   TO DO LIST:
//  - Look at numbers-at-length matrix...dimensioned by year, maturity, shell condition, sex, size bin
//  - Add routine to calculate reference points
//  - Add forecast routine
//  - Add warning section: use macro for warning(object,text)
//  - Add section to write new data file (enable easy labelling after first model attempt)
//  - Add simulation option, see LSMR model for demonstration 
//  =========================================================================================================

//  =========================================================================================================
GLOBALS_SECTION
  #include <admodel.h>
  #include <time.h>
  #include <contrib.h>

  time_t start,finish;
  long hour,minute,second;
  double elapsed_time;

  // Define objects for report file, echoinput, etc.
  /**
  \def report(object)
  Prints name and value of \a object on ADMB report %ofstream file.
  */
  #undef REPORT
  #define REPORT(object) report << #object "\n" << object << endl;

  /**
  \def echo(object)
  Prints name and value of \a object on ADMB echoinput %ofstream file.
  */
  #define echo(object) echoinput << #object << "\n" << object << endl;
  #define echotxt(object,text) echoinput << object << "\t" << text << endl;

  /**
  \def check(object)
  Prints name and value of \a object on ADMB check %ofstream file.
  */
  #define check(object) checkfile << #object << "\n" << object << endl;

  // Open output files using ofstream
  ofstream echoinput("echoinput.gm");
  ofstream checkfile("checkfile.gm");
  ofstream warning("warning.gm");

  // Define some adstring variables for use in output files:
  adstring version;
  adstring version_short;
  
// =========================================================================================================
TOP_OF_MAIN_SECTION
  time(&start);
  arrmblsize = 50000000;
  gradient_structure::set_GRADSTACK_BUFFER_SIZE(1.e7);
  gradient_structure::set_CMPDIF_BUFFER_SIZE(1.e7);
  gradient_structure::set_MAX_NVAR_OFFSET(5000);
  gradient_structure::set_NUM_DEPENDENT_VARIABLES(5000);

// =========================================================================================================
DATA_SECTION
  // Create strings with version information:
  !!version+="Gmacs_V1.03_2014/01/11_using_ADMB_11.1";
  !!version_short+="Gmacs V1.02";
  !! echoinput << version << endl;
  !! echoinput << ctime(&start) << endl;
  
  number incc; 
  number incd;
  !! incc = 0.00001; ///< some constant for likelihoods
  !! incd = 0.0001;  ///< som other constant used

// ---------------------------------------------------------------------------------------------------------
// STARTER FILE
  // Open Starter file (starter.gm)
  !! ad_comm::change_datafile_name("starter.gm"); 
  !! cout << " Reading information from starter file" << endl;
  !! echoinput << " Start reading starter file" << endl;

  // Read data, control, and size transition file names, then echo:
  init_adstring data_file;
  init_adstring control_file;
  init_adstring size_trans_file;

  !! echotxt(data_file, "data file");
  !! echotxt(control_file, "control file");

  // Read various option values, then echo:
  init_int verbose;            // Display detail to screen (option 1/0)
  init_int final_phase;        // Stop estimation after this phase
  init_int use_pin;            // Use a .pin file to get initial parameters (option 1/0)
  init_int read_growth;        // Read growth transition matrix file (option 1/0)

  !! echotxt(verbose, " display detail");
  !! echotxt(final_phase, " final phase");
  !! echotxt(use_pin, " use parameter in file (*.pin)");
  !! echotxt(read_growth, " read growth transition matrix data file");

  // Print EOF confirmation to screen and echoinput, warn otherwise:
  init_int eof_starter;

  !! if(eof_starter!=999) {cout << " Error reading starter file \n EOF = "<< eof_starter << endl; exit(1);}
  !! cout << " Finished reading starter file \n" << endl;
  !! echotxt(eof_starter," EOF: finished reading starter file \n");

// ---------------------------------------------------------------------------------------------------------
// DATA FILE (MAIN)
  // Open main data file (*.dat):
  !! ad_comm::change_datafile_name(data_file);
  !! cout << " Reading main data file" << endl;
  !! echoinput << " Start reading main data file" << endl;

  //Initialize some counters:
  int i; 
  int j;
  int iyr;
  int iclass;
  int jclass;
  int ifleet;
  int isurvey;
  int last;
  
  // Read input from main data file:
  init_int styr;        ///< Start year
  init_int endyr;       ///< End year
  init_number tstep;    ///< Time-step

  !! echotxt(styr,  " Start year");
  !! echotxt(endyr, " End year");
  !! echotxt(tstep, " Time-step");
  
  init_int nsex;        ///< Number of sexes  
  init_int nfleet;      ///< Number of fishing fleets
  init_int nsurvey;     ///< Number of surveys
  init_int nclass;      ///< Number of size classes
  init_int ndclass;     ///< Number of size classes (in the data)
  
  init_imatrix class_link(1,nclass,1,2);  ///< Link between data size-classes and model size-classs
   
  !! echotxt(nsex,    " Number of sexes");
  !! echotxt(nfleet,  " Number of fleets");
  !! echotxt(nsurvey, " Number of surveys")
  !! echotxt(nclass,  " Number of size classes");
  !! echotxt(ndclass, " Number of size classes for data");
  
  !! echo(class_link);

  init_vector catch_units(1,nfleet);        ///< Catch units (pot discards; + other fleets) [1=biomass (tons);2=numbers]
  init_vector catch_multi(1,nfleet);        ///< Additional catch scaling multipliers [1 for no effect]
  init_vector survey_units(1,nsurvey);      ///< Survey units [1=biomass (tons);2=numbers]
  init_vector survey_multi(1,nsurvey);      ///< Additional survey scaling multipliers [1 for no effect]
  init_int ncatch_obs;                      ///< Number of catch lines to read
  init_int nsurvey_obs;                     ///< Number of survey lines to read
  init_number survey_time;                  ///< Time between survey and fishery (for projections)  

  // Read fleet specifications and determine number with catch retained or discarded etc:
  init_imatrix fleet_control(1,nfleet,1,3);    ///< Fleet control matrix

  int nfleet_ret;                  ///< Number of fleets for retained catch data
  int nfleet_dis;                  ///< Number of fleets for discarded catch data (with link to above retained catch)
  int nfleet_byc;                  ///< Number of fleets for bycatch data only
  int nfleet_act;                  ///< Number of active distinct fleets

 LOCAL_CALCS
    nfleet_ret = 0;
    nfleet_dis = 0;
    nfleet_byc = 0;

    for (ifleet=1; ifleet<=nfleet; ifleet++)
    {
      switch (fleet_control(ifleet,2)) 
      {
        case 1 : 
          nfleet_ret += 1;
          break;
        case 2 : 
          nfleet_dis += 1;
          break;
        case 3 : 
          nfleet_byc += 1;
          break;
      } 
    } 
    nfleet_act = nfleet_ret + nfleet_byc;         ///< Determine number of active distinct fleets
 END_CALCS

  init_matrix catch_data(1,ncatch_obs,1,5);       ///< Catch data matrix, one line per ncatch_obs, requires year, season, fleet, observation
  matrix catch_biom_obs(1,nfleet,styr,endyr);     ///< Catch observations (biomass), per fleet
  matrix catch_num_obs(1,nfleet,styr,endyr);      ///< Catch observations (numbers), per fleet

 LOCAL_CALCS
  catch_biom_obs.initialize();
  catch_num_obs.initialize();
  
  for (int i=1; i<=ncatch_obs; i++)
  {
    catch_biom_obs(catch_data(i,3),catch_data(i,1)) = catch_data(i,5);
    catch_num_obs(catch_data(i,3),catch_data(i,1))  = catch_data(i,5);
  }

  check(catch_biom_obs);
  check(catch_num_obs);
  
  for (ifleet=1; ifleet<=nfleet; ifleet++)
  {
    for (iyr=styr; iyr<=endyr; iyr++)
    { 
     catch_biom_obs(ifleet,iyr) *= discard_mort(ifleet) * catch_multi(ifleet);
     catch_num_obs(ifleet,iyr) *= discard_mort(ifleet) * catch_multi(ifleet);
    }
  }
 END_CALCS

  !! echotxt(catch_units,  " Catch units");
  !! echotxt(catch_multi,  " Catch multipliers");
  !! echotxt(ncatch_obs,   " Number of lines of catch data");
  !! echo(catch_data);

  init_matrix survey_data(1,nsurvey_obs,1,6);       ///< Survey data matrix, one line per nsurvey_obs, requires year, season, survey, sex, observation, and error
  ivector nobs_survey(1,nsurvey);                   ///< Number of observations, per survey

 LOCAL_CALCS
  nobs_survey.initialize();
  for (i=1; i<=nsurvey_obs; i++)
  {
    nobs_survey(survey_data(i,3))++;
  }
 END_CALCS

  !! check(nobs_survey);
  
  imatrix yr_survey(1,nsurvey,1,nobs_survey);       ///< Years with survey data, per survey
  matrix survey_biom_obs(1,nsurvey,1,nobs_survey);  ///< Survey observations (biomass), per survey
  matrix survey_num_obs(1,nsurvey,1,nobs_survey);   ///< Survey observation (numbers), per survey
  matrix survey_var(1,nsurvey,1,nobs_survey);       ///< Survey variance values (input CV), per survey
 
 LOCAL_CALCS
  survey_var.initialize();
  survey_biom_obs.initialize();
  survey_num_obs.initialize();
  
  ivector iobs_sv(1,nsurvey);       ///< Counter for number of obs. for each survey
  iobs_sv.initialize();

  for (i=1; i<=nsurvey_obs; i++)
  {
    int isrv=survey_data(i,3);
    iobs_sv(isrv)++;
    yr_survey(isrv,iobs_sv(isrv)) = survey_data(i,1);
    if (survey_units(isrv)==1)
      survey_biom_obs(isrv,iobs_sv(isrv)) = survey_data(i,5);
    else 
      survey_num_obs(isrv,iobs_sv(isrv)) = survey_data(i,5);
    survey_var(isrv,iobs_sv(isrv)) = log(1+square(survey_data(i,6)));
  }  
  
  for (isurvey=1; isurvey<=nsurvey; isurvey++)  
  {
    for (i=1; i<=nobs_survey(isurvey); i++)
    { 
      survey_biom_obs(isurvey,i) *= survey_multi(isurvey);
      survey_num_obs(isurvey,i) *= survey_multi(isurvey);
    }
  }
 END_CALCS

 !! check(yr_survey);
 !! check(survey_biom_obs);
 !! check(survey_num_obs);
 !! check(survey_var);

  // Note: For likelihood, compute input survey variance here (assumes data file input values are CVs)

  // Q: Some pre-processing of these data required. See simple.tpl for example.
  // TODO: Multiply these catch and survey data by multipliers provided. Simple.tpl Line 56+

  !! echotxt(survey_units, " Survey units");
  !! echotxt(survey_multi, " Survey multipliers");
  !! echotxt(survey_time,  " Time between survey and fishery");
  !! echotxt(nsurvey_obs,  " Number of lines of survey data");
  !! echo(survey_data);

  init_vector discard_mort(1,nfleet);               ///< Discard mortality (per fishery)
  init_vector hg(styr,endyr);                       ///< Retention value for each year (highgrading)
  init_matrix catch_time(1,nfleet_act,styr,endyr);  ///< Timing of each fishery (as fraction of time-step)
  init_matrix effort(1,nfleet_act,styr,endyr);      ///< Effort by fishery
  init_imatrix f_new(1,nfleet_act,1,5);             ///< Alternative f estimators (overwrite others)

  !! echo(discard_mort);
  !! echo(hg);
  !! echo(catch_time);
  !! echo(effort);
  !! echo(f_new);

  // Determine which F values will be computed using effort (f_new) if applicable: 
  ivector ncatch_f(1,nfleet_act);
 
 LOCAL_CALCS
  for (ifleet=1; ifleet<=nfleet_act; ifleet++)
  {
    ncatch_f(ifleet) = 0;
    for (iyr=styr; iyr<=endyr; iyr++) 
      if (effort(ifleet,iyr) > 0) 
      {
        if (f_new(ifleet,1) == 0 | iyr < f_new(ifleet,2) | iyr > f_new(ifleet,3))
          ncatch_f(ifleet) += 1;
      }
  }
 END_CALCS
  
  !! echotxt(ncatch_f, " Number of F's (calculated)")
  
  // Read in the length frequency data:
  init_int nlf_obs;                                 ///< Number of length frequency lines to read for fishing fleets 
  init_matrix lf_data(1,nlf_obs,1,ndclass+7);       ///< Length frequency data, one line per nlf_obs, requires year, season, fleet, sex, maturity, shell cond., effective sample size, then data vector 
  ivector nlf_fleet(1,nfleet)     ;                 ///< Number of years of lf data per fleet
 
 LOC_CALCS 
  nlf_fleet.initialize();
  for (i=1; i<=nlf_obs; i++) 
  {
    nlf_fleet(int(lf_data(i,3)))++ ;
  }
 END_CALCS
  
  imatrix yr_fleet_lf(1,nfleet,1,nlf_fleet);                ///< Years with lf data, by fleet
  matrix ss_fleet_lf(1,nfleet,1,nlf_fleet);                 ///< Effective sample sizes, by fleet
  3darray fleet_lf(1,nfleet,1,nlf_fleet,1,ndclass);         ///< Length-frequency data (ndclass), by fleet (can be ragged array)
  3darray fleet_lf_obs(1,nfleet,1,nlf_fleet,1,nclass);      ///< Length-frequency data (nclass), by fleet (can be ragged array)
 
 LOC_CALCS 
  ivector iobs_fl(1,nfleet);                                ///< Counter for number of obs within each fleet
  iobs_fl.initialize();
  for (i=1; i<=nlf_obs; i++) 
  {
    ifleet = int(lf_data(i,3));
    iobs_fl(ifleet)++;
    yr_fleet_lf(ifleet,iobs_fl(ifleet)) = (lf_data(i,1));
    ss_fleet_lf(ifleet,iobs_fl(ifleet)) = lf_data(i,7);
    
    for (iclass=1; iclass<=nclass; iclass++)
      fleet_lf_obs(ifleet,iobs_fl(ifleet),iclass) = sum(lf_data(i)(7+class_link(iclass,1),7+class_link(iclass,2)));
      // FIX: fleet_lf(ifleet,iobs_fl(ifleet),iclass) = lf_data(i)(8,(ndclass+7)).shift(1);
  }
 END_CALCS

  !! echotxt(nlf_obs,  " Number of length freq lines to read");
  !! echo(lf_data);
  !! echo(nlf_fleet);
  !! echo(yr_fleet_lf);
  !! echo(ss_fleet_lf);
  !! echo(fleet_lf_obs);
  
  // Read in survey length frequency data:
  init_int nlfs_obs;                                ///< Number of survey length frequency lines to read
  init_matrix lfs_data(1,nlfs_obs,1,ndclass+5);     ///< Survey length frequency data, one line per nlfs_obs, requires year, season, survey, sex, effective sample size, then data vector
  ivector nlf_survey(1,nsurvey);                    ///< Number of years of survey lf data per survey

 LOC_CALCS 
  nlf_survey.initialize();
  for (i=1; i<=nlfs_obs; i++) 
  {
    nlf_survey(int(lfs_data(i,3)))++ ;
  }
 END_CALCS
  
  imatrix yr_survey_lf(1,nsurvey,1,nlf_survey);                ///< Years with lf data, by survey
  matrix ss_survey_lf(1,nsurvey,1,nlf_survey);                 ///< Effective sample sizes, by survey
  3darray survey_lf(1,nsurvey,1,nlf_survey,1,ndclass);         ///< Length-frequency data (ndclass), by survey (can be ragged array)
  3darray survey_lf_obs(1,nsurvey,1,nlf_survey,1,nclass);      ///< Length-frequency data (nclass), by survey (can be ragged array)
 
 LOC_CALCS 
  iobs_sv.initialize();
  for (i=1; i<=nlfs_obs; i++) 
  {
    isurvey = int(lfs_data(i,3));
    iobs_sv(isurvey)++;
    yr_survey_lf(isurvey,iobs_sv(isurvey)) = (lfs_data(i,1));
    ss_survey_lf(isurvey,iobs_sv(isurvey)) = lfs_data(i,5);
    for (iclass=1; iclass<=nclass; iclass++)
    {
      survey_lf_obs(isurvey,iobs_sv(isurvey),iclass) = sum(lfs_data(i)(5+class_link(iclass,1),5+class_link(iclass,2)));
    }
    survey_lf(isurvey,iobs_sv(isurvey)) = lfs_data(i)(6,(ndclass+5)).shift(1);
  }
 END_CALCS

  !! echotxt(nlfs_obs, " Number of survey length freq lines to read");
  !! echo(lfs_data);
  !! echo(nlf_survey);
  !! echo(yr_survey_lf);
  !! echo(ss_survey_lf);
  !! echo(survey_lf_obs);
  
  // Read in length, weight, fecundity vectors, then calculate equivalent vectors with nclass number of size-classes:
  init_vector mean_length(1,ndclass);       ///< Mean length vector input
  init_vector mean_weight(1,ndclass);       ///< Mean weight vector input
  init_vector fecundity_inp(1,ndclass);     ///< Fecundity vector input

  !! echo(mean_length);
  !! echo(mean_weight);
  !! echo(fecundity_inp);

  // Format length, weight, and fecundity vectors to model size-classes:
  vector length(1,nclass);                  ///< Length vector (mm) for model
  vector weight(1,nclass);                  ///< Weight (kg) vector for model
  vector fecundity(1,nclass);               ///< Fecundity (kg) vector for model

  vector surv_lf_store(1,ndclass);         ///< Survey lf total by data class

  !! checkfile << "Class length, weight, and fecundity" << endl;
  
 // TODO: Check surv_lf_store loop over nlfs_obs; only loops over first survey in simple.tpl (only first survey has data)
 LOCAL_CALCS
  int total;
  total = 0;
  for (iclass=1; iclass<=ndclass; iclass++)
  {
    surv_lf_store(iclass) = 0;
    for (iyr=1; iyr<=nlfs_obs; iyr++) surv_lf_store(iclass) += survey_lf(1,iyr,iclass);
    total += surv_lf_store(iclass);
  }
  if (verbose == 1) cout << "Survey sample sizes stored" << endl; // CHECK: WTF? Not storing sample sizes.

  for (iclass=1; iclass<=nclass; iclass++)
  {
    length(iclass) = 0; 
    weight(iclass) = 0; 
    fecundity(iclass) = 0; 
    total = 0;
    for (jclass=class_link(iclass,1); jclass<=class_link(iclass,2); jclass++)
    {
      length(iclass) += mean_length(jclass)*surv_lf_store(jclass);
      weight(iclass) += mean_weight(jclass)*surv_lf_store(jclass);
      fecundity(iclass) += fecundity_inp(jclass)*surv_lf_store(jclass);
      total += surv_lf_store(jclass);
    }
    length(iclass) /= total;
    weight(iclass) /= total;
    fecundity(iclass) /= total;
    checkfile << iclass << " " << length(iclass) << " " << weight(iclass) << " " << fecundity(iclass) << endl;
  }
  if (verbose == 1) cout << " Lengths, weights, and fecundity specified" << endl;
 END_CALCS

  // Read in capture, mark, recapture data:
  init_int ncapture_obs;                           ///< Number of capture data lines to read    
  init_int nmark_obs;                              ///< Number of mark data lines to read
  init_int nrecapture_obs;                         ///< Number of recapture data lines to read

  init_matrix capture_data(1,ncapture_obs,1,ndclass+3);         ///< Capture data, one line per ncapture_obs, requires years, fleet, sex, then data vector
  init_matrix mark_data(1,nmark_obs,1,ndclass+3);               ///< Mark data, one line per nmark_obs, requires years, fleet, sex, then data vector
  init_matrix recapture_data(1,nrecapture_obs,1,ndclass+3);     ///< Recapture data, one line per nrecapture_obs, requires years, fleet, sex, then data vector

  !! echotxt(ncapture_obs,   " Number of capture data lines");
  !! echotxt(nmark_obs,      " Number of mark data lines");
  !! echotxt(nrecapture_obs, " Number of recapture data lines")

  // Echo capture, mark, recapture data when appropriate:
 LOCAL_CALCS
  if(ncapture_obs > 0) 
  {
    echo(capture_data);
    echo(mark_data);
    echo(recapture_data);
  }
 END_CALCS
  
  // Print EOF confirmation to screen and echoinput, warn otherwise:
  init_int eof_data;
  
  !! if(eof_data!=999) {cout << " Error reading main data file \n EOF = "<< eof_data << endl; exit(1);}
  !! cout << " Finished reading main data file \n" << endl;
  !! echotxt(eof_data," EOF: finished reading main data file \n");

  
// ---------------------------------------------------------------------------------------------------------
// DATA FILE (GROWTH)
// This section is conditional on starter file flag (read growth matrix data file).
  
  // Declare objects to read in from growth data file:
  int styr_growth;        ///< Start year for growth data
  int endyr_growth;       ///< End year for growth data
  int ndclass_growth;     ///< Number of data classes for growth data

  !! ndclass_growth = 0;

 LOCAL_CALCS
  if(read_growth==1)
  {  
    // Open size transition file (*.dat) //
    ad_comm::change_datafile_name(size_trans_file);
    cout << " Reading size transition file" << endl;
    echoinput << " Start reading size transition file" << endl;
    // Read input from growth data file:
    *(ad_comm::global_datafile) >> styr_growth;
    *(ad_comm::global_datafile) >> endyr_growth;
    *(ad_comm::global_datafile) >> ndclass_growth;

    echotxt(styr_growth, " Start year for growth data");
    echotxt(endyr_growth, " End year for growth data");
    echotxt(ndclass_growth, " Number of growth data classes");
  }
 END_CALCS
  
  // Declare objects dependent on previous objects:
  ivector growth_bins(1,ndclass_growth);                                                  ///< Vector of growth data bins (lower length of each bin)
  3darray growth_data(styr_growth,endyr_growth,1,ndclass_growth-1,1,ndclass_growth-1);    ///< Array of year specific growth transition matrices  
  int eof_growth;    // Declare EOF check

 LOCAL_CALCS
  if(read_growth==1)
  {  
    *(ad_comm::global_datafile) >> growth_bins;
    *(ad_comm::global_datafile) >> growth_data;

    echo(growth_bins);
    echo(growth_data);

    *(ad_comm::global_datafile) >> eof_growth;
    
    // Print EOF confirmation to screen and echoinput, warn otherwise:
    if(eof_growth!=999) {cout << " Error reading size transition file\n EOF = " << eof_growth << endl; exit(1);}
    cout << " Finished reading size transition file \n" << endl;
    echotxt(eof_growth," EOF: finished reading size transition file \n");
  }
 END_CALCS

// ---------------------------------------------------------------------------------------------------------
// CONTROL FILE

  // Open control file (*.ctl) //
  !! ad_comm::change_datafile_name(control_file);
  !! cout << " Reading control file" << endl;
  !! echoinput << " Start reading control file" << endl;
  
  // Specifiy number of general parameters to be read in:
  int ntheta;
  !! ntheta = 2;
  
  // Read general input from control file:
  init_matrix theta_control(1,ntheta,1,13);     ///< General parameter matrix, with specifications
  matrix trans_theta_control(1,13,1,ntheta);    ///< Transpose of general parameter matrix
  vector theta_init(1,ntheta);                  ///< Vector of general parameter specs - initial values
  vector theta_lbnd(1,ntheta);                  ///< Vector of general parameter specs - lower bound values
  vector theta_ubnd(1,ntheta);                  ///< Vector of general parameter specs - upper bound values        
  ivector theta_phz(1,ntheta);                  ///< Vector of general parameter specs - phase values
  ivector theta_prior(1,ntheta);                ///< Vector of general parameter specs - prior type
  vector theta_pmean(1,ntheta);                 ///< Vector of general parameter specs - prior mean values
  vector theta_psd(1,ntheta);                   ///< Vector of general parameter specs - prior s.d. values
  ivector theta_cov(1,ntheta);                  ///< Vector of general parameter specs - covariate type
  ivector theta_dev(1,ntheta);                  ///< Vector of general parameter specs - deviation type
  vector theta_dsd(1,ntheta);                   ///< Vector of general parameter specs - deviation s.d.
  ivector theta_dmin(1,ntheta);                 ///< Vector of general parameter specs - deviation min. year
  ivector theta_dmax(1,ntheta);                 ///< Vector of general parameter specs - deviation max. year
  ivector theta_blk(1,ntheta);                  ///< Vector of general parameter specs - block number (for time-varying paramters)

  !! echo(theta_control);

  // Fill matrices and vectors created above:
 LOC_CALCS
    trans_theta_control = trans(theta_control);
    theta_init          = trans_theta_control(1);
    theta_lbnd          = trans_theta_control(2);
    theta_ubnd          = trans_theta_control(3);
    theta_phz           = ivector(trans_theta_control(4));
    theta_prior         = ivector(trans_theta_control(5));
    theta_pmean         = trans_theta_control(6);
    theta_psd           = trans_theta_control(7);
    theta_cov           = ivector(trans_theta_control(8));
    theta_dev           = ivector(trans_theta_control(9));
    theta_dsd           = trans_theta_control(10);
    theta_dmin          = ivector(trans_theta_control(11));
    theta_dmax          = ivector(trans_theta_control(12));
    theta_blk           = ivector(trans_theta_control(13));
 END_CALCS

  // Read in specifications relating to recruitment:
  init_int sr_lag;                                   ///< Lag to recruitment
  init_int sr_type;                                  ///< Form of stock recruitment relationship

  !! echotxt(sr_lag, " Lag to recruitment (years)");
  !! echotxt(sr_type, " Form of stock-recruitment relationship");

  // Read in pointers for time-varying natural mortality:
  init_vector M_pnt(styr,endyr);                     ///< Pointers to blocks for time-varying natural mortality

  int nMadd_parms;                                   ///< Number of M additional parameters
  !! nMadd_parms = max(M_pnt);                   

  !! echo(M_pnt);
  !! echotxt(nMadd_parms, " Number of additional natural mortality parameters");
  
  // Read in naturaly mortality parameter specifications:
  init_matrix madd_control(1,nMadd_parms,1,4);       ///< Natural mort. parameter matrix, with speciifications           
  matrix trans_madd_control(1,4,1,nMadd_parms);      ///< Transponse of natural mort. parameter matrix    
  vector madd_init(1,nMadd_parms);                   ///< Vector of natural mort. parameter specs - initial values  
  vector madd_lbnd(1,nMadd_parms);                   ///< Vector of natural mort. parameter specs - lower bounds
  vector madd_ubnd(1,nMadd_parms);                   ///< Vector of natural mort. parameter specs - upper bounds      
  ivector madd_phz(1,nMadd_parms);                   ///< Vector of natural mort. parameter specs - phase values

  !! echo(madd_control);

  // Fill matrices and vectors created above:
 LOCAL_CALCS
    trans_madd_control = trans(madd_control);
    madd_init = trans_madd_control(1);
    madd_lbnd = trans_madd_control(2);
    madd_ubnd = trans_madd_control(3);
    madd_phz = ivector(trans_madd_control(4));
 END_CALCS

  // Read in pointers for time-varying fishery and survey selectivity:
  init_imatrix selex_fleet_pnt(1,nfleet_act,styr,endyr);          ///< Pointers to blocks for time-varying fishing selectivity
  init_imatrix selex_survey_pnt(1,nsurvey,styr,endyr+1);          ///< Pointers to blocks for time-varying survey selectivity

  !! echo(selex_fleet_pnt);
  !! echo(selex_survey_pnt);

  // Determine number of different selectivity functions/patterns to estimate:
  int nselex;
  int nselex_pats;
  int nselex_pars;

  !! nselex_pats = max(selex_survey_pnt);
  !! echotxt(nselex_pats, " Total number of selectivity patterns");

  // TODO: For selex types, check AEP BBRKC document for what each type is.
  // Read in specifications for each selectivity pattern and determine number of parameters to estimate:
  matrix selex_type(1,nselex_pats,1,4);    ///< Selectivity types for each fleet/survey by time-block
  
  // TODO: The selex_type matrix can probably be read in directly, then the loop over the columns should work the same.
 LOCAL_CALCS
  nselex = 0;
  for (i=1; i<=nselex_pats; i++)
  {
    *(ad_comm::global_datafile) >> selex_type(i,1) >> selex_type(i,2) >> selex_type(i,3);
    if (selex_type(i,2) == 1) nselex += 2;
    if (selex_type(i,2) == 2) nselex += nclass;
    if (selex_type(i,2) == 3) nselex += 1;
  }
  nselex_pars = nselex;
  echo(selex_type);
  echotxt(nselex_pars, " Total number of selectivity parameters");

  // Fill last column of selex_type matrix, for use in Set_selex function.
  i = 0;
  for (j=1; j<=nselex_pats; j++)
   {
    selex_type(j,4) = i;
    if (selex_type(j,2)==1) last = 2;
    if (selex_type(j,2)==2) last = nclass;
    if (selex_type(j,2)==3) last = 1;
    i += last;
   }
  check(selex_type);
 END_CALCS

  //TODO: Add more selectivity options above as necessary for next example models. See LSMR code for example.

  // Read in selectivity parameter specifications:
  init_matrix selex_control(1,nselex_pars,1,4);      ///< Selectivity parameter matrix, with specifications
  matrix trans_selex_control(1,4,1,nselex_pars);     ///< Transpose of selectivity parameter matrix
  vector selex_init(1,nselex_pars);                  ///< Vector of selex parameter specs - initial values
  vector selex_lbnd(1,nselex_pars);                  ///< Vector of selex parameter specs - lower bounds
  vector selex_ubnd(1,nselex_pars);                  ///< Vector of selex parameter specs - upper bounds
  ivector selex_phz(1,nselex_pars);                  ///< Vector of selex parameter specs - phase values
  
  !! echo(selex_control);

  // Fill matrices and vectors created above:
 LOCAL_CALCS
    trans_selex_control = trans(selex_control);
    selex_init = trans_selex_control(1);
    selex_lbnd = trans_selex_control(2);
    selex_ubnd = trans_selex_control(3);
    selex_phz = ivector(trans_selex_control(4));
 END_CALCS

  // Read in pointers for time-varying fishery retention:
  int nreten_pars;
  init_imatrix reten_fleet_pnt(1,nfleet_ret,styr,endyr);

  //TODO: Check if above row for retention applies to discard fishery or to linked retained fishery:
  
  !! nreten_pars = reten_fleet_pnt.indexmax();
  !! nreten_pars *= nclass;

  //TODO: This code assumes only one type of retention function at the moment. Update as necessary.
  
  !! echotxt(nreten_pars, " Total number of retention parameters");

  // Read in retention parameter specifications:
  init_matrix reten_control(1,nreten_pars,1,4);       ///< Retention parameter matrix, with speciifications           
  matrix trans_reten_control(1,4,1,nreten_pars);      ///< Transponse of retention parameter matrix    
  vector reten_init(1,nreten_pars);                   ///< Vector of retention parameter specs - initial values  
  vector reten_lbnd(1,nreten_pars);                   ///< Vector of retention parameter specs - lower bounds
  vector reten_ubnd(1,nreten_pars);                   ///< Vector of retention parameter specs - upper bounds      
  ivector reten_phz(1,nreten_pars);                   ///< Vector of retention parameter specs - phase values

  !! echo(reten_control);

  // Fill matrices and vectors created above:
 LOCAL_CALCS
  trans_reten_control = trans(reten_control);
  reten_init = trans_reten_control(1);
  reten_lbnd = trans_reten_control(2);
  reten_ubnd = trans_reten_control(3);
  reten_phz = ivector(trans_reten_control(4));
 END_CALCS

  // Read in pointers for time-varying survey catchability:
  int nsurveyq_pars;
  init_imatrix surveyq_pnt(1,nsurvey,styr,endyr+1);

  !! nsurveyq_pars = max(surveyq_pnt);

  !! echo(surveyq_pnt);
  !! echotxt(nsurveyq_pars, " Total number of survey Q patterns");

  // Read in flag for number of surveys in a sub-area of the main survey area:
  init_int nsubsurvey;
  init_imatrix subsurvey(1,nsubsurvey,1,2);

  !! echotxt(nsubsurvey, " Number of sub-surveys");
  !! if(nsubsurvey > 0) echo(subsurvey);

  // Read in survey catchability parameter specifications:
  init_matrix surveyq_control(1,nsurveyq_pars,1,7);         ///< Survey Q parameter matrix, with speciifications           
    matrix trans_surveyq_control(1,7,1,nsurveyq_pars);      ///< Transponse of survey Q parameter matrix    
    vector surveyq_init(1,nsurveyq_pars);                   ///< Vector of survey Q parameter specs - initial values  
    vector surveyq_lbnd(1,nsurveyq_pars);                   ///< Vector of survey Q parameter specs - lower bounds
    vector surveyq_ubnd(1,nsurveyq_pars);                   ///< Vector of survey Q parameter specs - upper bounds      
    ivector surveyq_phz(1,nsurveyq_pars);                   ///< Vector of survey Q parameter specs - phase values
    ivector surveyq_prior(1,nsurveyq_pars);                 ///< Vector of survey Q parameter specs - prior types
    vector surveyq_pmean(1,nsurveyq_pars);                  ///< Vector of survey Q parameter specs - prior mean values
    vector surveyq_psd(1,nsurveyq_pars);                    ///< Vector of survey Q parameter specs - prior s.d. values

   !! echo(surveyq_control);

  // Fill matrices and vectors created above:
 LOCAL_CALCS
    trans_surveyq_control = trans(surveyq_control);
    surveyq_init          = trans_surveyq_control(1);
    surveyq_lbnd          = trans_surveyq_control(2);
    surveyq_ubnd          = trans_surveyq_control(3);
    surveyq_phz           = ivector(trans_surveyq_control(4));
    surveyq_prior         = ivector(trans_surveyq_control(5));
    surveyq_pmean         = trans_surveyq_control(6);
    surveyq_psd           = trans_surveyq_control(7);  
 END_CALCS

  // Read in initial N parameter specifications:
  init_matrix lognin_control(1,nclass,1,4);         ///< Initial N parameter matrix, with specifications
  matrix trans_lognin_control(1,4,1,nclass);        ///< Transpose of initial N parameter matrix
  vector lognin_init(1,nclass);                     ///< Vector of initial N parameter specs - initial values
  vector lognin_lbnd(1,nclass);                     ///< Vector of initial N parameter specs - lower bounds
  vector lognin_ubnd(1,nclass);                     ///< Vector of initial N parameter specs - upper bounds
  ivector lognin_phz(1,nclass);                     ///< Vector of initial N parameter specs - phase values
  
  !! echo(lognin_control);

  // Fill matrices and vectors created above:
 LOCAL_CALCS
    trans_lognin_control = trans(lognin_control);
    lognin_init          = trans_lognin_control(1);
    lognin_lbnd          = trans_lognin_control(2);
    lognin_ubnd          = trans_lognin_control(3);
    lognin_phz           = ivector(trans_lognin_control(4));  
 END_CALCS

  // Read in selectivity parameter specifications:
  init_matrix gtrans_control(1,nclass-1,1,4);        ///< Growth transition parameter matrix, with specifications
  matrix trans_gtrans_control(1,4,1,nclass-1);       ///< Transpose of initial N parameter matrix
  vector gtrans_init(1,nclass-1);                    ///< Vector of growth trans. parameter specs - initial values
  vector gtrans_lbnd(1,nclass-1);                    ///< Vector of growth trans. parameter specs - lower bounds
  vector gtrans_ubnd(1,nclass-1);                    ///< Vector of growth trans. parameter specs - upper bounds
  ivector gtrans_phz(1,nclass-1);                    ///< Vector of growth trans. parameter specs - phase values
  
  !! echo(gtrans_control);

  // Fill matrices and vectors created above:
 LOCAL_CALCS
    trans_gtrans_control = trans(gtrans_control);
    gtrans_init = trans_gtrans_control(1);
    gtrans_lbnd = trans_gtrans_control(2);
    gtrans_ubnd = trans_gtrans_control(3);
    gtrans_phz = ivector(trans_gtrans_control(4));  
 END_CALCS

  // Determine number of prior terms, and create objects to hold these values:
  int nprior_terms;
  int nlike_terms;
    
  !! nprior_terms = (nfleet_act) + 1 + nfleet + nsurveyq_pars + 1 + 1;  
  !! nlike_terms = (nfleet)*2+ (nfleet_act) + (nsurvey)*2;
  // TODO: Check this section works in the general sense when applying to other species.
    
  !! echotxt(nprior_terms, " Number of prior terms");
  !! echotxt(nlike_terms, " Number of likelihood terms");
    
  // Read in prior and data re-weighting values:  

  init_vector prior_weight(1,nprior_terms);                 ///< Weights on the priors
  init_vector data_weight(1,nlike_terms);                   ///< Weights on the data

  !! echo(prior_weight);
  !! echo(data_weight);

  // Print EOF confirmation to screen and echoinput, warn otherwise:
  init_int eof_control;

  !! if(eof_control!=999) {cout << " Error reading control file\n EOF = " << eof_control << endl; exit(1);}
  !! cout << " Finished reading control file \n" << endl;
  !! echotxt(eof_data," EOF: finished reading control file \n");

  // TODO: Check these extra objects below, and make them Gmacs format if required.

  //3darray FleetObsLF(1,nfleet,1,maxFleetLF,1,nclass)        // Catch/bycatch Lfs (by model classes)
  //3darray SurveyObsLF(1,nsurvey,1,maxSurveyLF,1,nclass)     // Survey Lfs (by model classes)
  
  // Stuff related to the SR relationship
  int IsB0;                                         // Constant recruitment?
  int SR_rel;                                       // Form of SR_Relationship

// ---------------------------------------------------------------------------------------------------------
// FORECAST FILE

  // Open forecast file (forecast.gm):
  !! ad_comm::change_datafile_name("forecast.gm");
  !! cout << " Reading forecast file" << endl;
  !! echoinput << " Start reading forecast file" << endl;
  
  init_int bmsy_start;
  init_int bmsy_end;

  !! echotxt(bmsy_start, " BMSY start year");
  !! echotxt(bmsy_end, " BMSY end year");

  // Print EOF confirmation to screen and echoinput, warn otherwise:
  init_int eof_forecast;

  !! if(eof_forecast!=999) {cout << " Error reading forecast file\n EOF = " << eof_forecast << endl; exit(1);}
  !! cout << " Finished reading forecast file \n" << endl;
  !! echotxt(eof_data," EOF: finished reading forecast file \n");

  !! cout << " Successfully read all input files. \n" << endl;

// =========================================================================================================
// GENERAL CALCS SECTION

  // Create count of active parameters and derived quantities
  int par_count;
  int active_count;
  int active_parms;
  ivector active_parm(0,ntheta);  //  Pointer from active list to the element of the full parameter list to get label

  // TODO: Add active_parm pointer list for labelling active parameters in report file.

  // Create dummy datum for use when max phase == 0
  number dummy_datum;
  int dummy_phase;
  !! dummy_datum = 1;
  !! if(final_phase<=0) {dummy_phase=0;} else {dummy_phase=-6;}

  // Adjust the phases to negative if beyond final_phase and find resultant max_phase:
  int max_phase;
 
 LOC_CALCS
  cout << " Count parameters and get max phase, adjust phases if required" << endl;
  max_phase=1;
  active_count=0;
  par_count=0;
  active_parm(0,ntheta)=0;
    
  for(i=1; i<=ntheta; i++)
  { 
    par_count++;
    if(theta_phz(i) > final_phase) theta_phz(i)=-1;
    if(theta_phz(i) > max_phase) max_phase=theta_phz(i);
    if(theta_phz(i) >= 0)
      active_count++; active_parm(active_count)=par_count;
  }
  active_parms=active_count;
 END_CALCS
  !! cout << " Number of active parameters is " << active_parms << endl;
  !! cout << " Maximum phase for estimation is " << max_phase << "\n" << endl;

  !! check (theta_phz);
  !! check (ntheta);
  !! check (par_count); 
  !! check (active_parm);
  !! check (active_parms);
  // TODO: Adjust this section to include other parameters not specified in the general paramter matrix 'theta'.

// =========================================================================================================
PARAMETER_SECTION
  
  // Create dummy parameter that will be estimated when final_phase is set to 0
  init_bounded_number dummy_parm(0,2,dummy_phase);  //  Dummy parameter estimated in phase 0 

  !! check(dummy_parm);
  
  // Initialize general parameter matrix:
  init_bounded_number_vector theta_parms(1,ntheta,theta_lbnd,theta_ubnd,theta_phz);          ///< Vector of general parameters
  
  number logRbar;
  number M0;

  !! check(theta_parms);

  // Initialize other parameter matrices:
  init_bounded_number_vector Madd_parms(1,nMadd_parms,madd_lbnd,madd_ubnd,madd_phz);                   ///< Vector of increments in M parameters
  init_bounded_number_vector gtrans_parms(1,nclass-1,gtrans_lbnd,gtrans_ubnd,gtrans_phz);             ///< Vector of growth transition parameters
  init_bounded_number_vector selex_parms(1,nselex_pars,selex_lbnd,selex_ubnd,selex_phz);              ///< Vector of selectivity parameters
  init_bounded_number_vector reten_parms(1,nreten_pars,reten_lbnd,reten_ubnd,reten_phz);              ///< Vector of retention parameters
  init_bounded_number_vector surveyq_parms(1,nsurveyq_pars,surveyq_lbnd,surveyq_ubnd,surveyq_phz);    ///< Vector of survey Q parameters
  init_bounded_number_vector lognin_parms(1,nclass,lognin_lbnd,lognin_ubnd,lognin_phz);               ///< Vector of initial N parameters
   
  !! check(Madd_parms);
  !! check(gtrans_parms);
  !! check(selex_parms);
  !! check(reten_parms);
  !! check(surveyq_parms);
  !! check(lognin_parms);

  !! check(ncatch_f);

  // Initialize predicted catch and recruitment parameters:
  init_bounded_vector_vector f_est(1,nfleet_act,1,ncatch_f,0,1,1);         ///< Vector of predicted f values
  init_vector recdev(styr,endyr,1);                                        ///< Vector of recruitment deviations
  
  !! cout << " All parameters declared \n" << endl;
  !! checkfile << " All parameters declared" << endl;

  // Create model vectors, matrices, and arrays:
  matrix f_all(1,nfleet_act,styr,endyr);                      ///< Fishing mortality matrix 

  matrix N(styr,endyr+1,1,nclass);                            ///< Numbers-at-age matrix
  matrix S(styr,endyr,1,nclass);                              ///< Survival matrix (general)
  3darray S_fleet(1,nfleet_act,styr,endyr,1,nclass);          ///< Survival matrices (one for each distinct fishery)
  matrix exp_rate(1,nfleet_act,styr,endyr);                   ///< Exploitation rate matrix
  matrix strans(1,nclass,1,nclass);                           ///< Size-transition matrix
  
  matrix reten(styr,endyr,1,nclass);                          ///< Male retention matrix 
  // TODO: The above matrix was retain_males in old code. Should this be sex-distinct?

  3darray selex_fleet(1,nfleet_act,styr,endyr,1,nclass);      ///< Distinct fishery selectivity array
  3darray selex_survey(1,nsurvey,styr,endyr+1,1,nclass);      ///< Survey selectivity array
  vector surveyq(1,nsurvey);                                  ///< Survey Q vector
  matrix selex_all(1,nselex_pats,1,nclass);                   ///< All selectivity matrix

  3darray fleet_lf_pred(1,nfleet,1,nlf_fleet,1,nclass);       ///< Predicted catches (numbers) by class
  matrix catch_biom_pred(1,nfleet,styr,endyr);               ///< Predicted catch weights
  matrix catch_num_pred(1,nfleet,styr,endyr);                ///< Predicted catch numbers
  
  3darray survey_lf_pred(1,nsurvey,1,nlf_survey,1,nclass);    ///< Survey LF from the model
  matrix survey_biom_pred(1,nsurvey,1,nobs_survey);            ///< Predicted survey weights
  matrix survey_num_pred(1,nsurvey,1,nobs_survey);             ///< Predicted survey numbers
  vector q_effort(1,nfleet_act);                              ///< Effort q
  vector M(styr,endyr);                                       ///< Natural mortality
  vector f_direct(styr,endyr);                                ///< Fishing mortality
  
  // Initialize the components of the objective function:
  vector prior_val(1,nprior_terms);                           ///< Objective function prior values
  vector like_val(1,nlike_terms);                             ///< Objective function likelihood values
  objective_function_value fobj;                              ///< Objective function value to be minimised

  // Stuff related to the SR relationship
  number f_multi;                                             ///< Passed F multiplier
  number mbio_out;                                            ///< Predicted mature male biomass (MMB)
  number f_35;                                                ///< F35
  number sbpr_35;                                             ///< SBPR35 (used to define BMSY)
  number rec_out;                                             ///< Predicted recruitment  
  number catch_out;                                           ///< Predicted catch
  vector mbio_proj(1,1000);                                   ///< Future MMB (projected)
  vector f_mort(1,nfleet_byc);                                ///< Bycatch (kill) fleet Fs

  number rec_zero;                                            ///< Virgin recruitment 
  number steep;                                               ///< Stock-recruit steepness 
  number mbio_zero;                                           ///< Virgin MMB 
  vector mbio(styr,endyr);                                    ///< Mature male biomass (MMB)
  sdreport_vector logmbio(styr,endyr);                        ///< Log of MMB
  vector recruits(styr,endyr);                                ///< Recruitment vector
  sdreport_vector logrecruits(styr,endyr);                    ///< Log of recruitment vector
  sdreport_vector logrecmbio(styr,endyr-sr_lag);              ///< Log of recruits-per-spawner

  // TODO: See example for more complicated selectivity options from LSMR.tpl.

// =========================================================================================================
PRELIMINARY_CALCS_SECTION

  // Initialize the dummy parameter as needed:
  if(final_phase<=0) {dummy_parm=0.5;} else {dummy_parm=1.0;}

  // Set the initial values of parameters:
  int j;

  for (j=1; j<=ntheta; j++) theta_parms(j) = theta_init(j);
  for (j=1; j<=nMadd_parms; j++) Madd_parms(j) = madd_init(j);  
  for (j=1; j<=nclass-1; j++) gtrans_parms(j) = gtrans_init(j);
  for (j=1; j<=nselex_pars; j++) selex_parms(j) = selex_init(j);
  for (j=1; j<=nreten_pars; j++) reten_parms(j) = reten_init(j);
  for (j=1; j<=nsurveyq_pars; j++) surveyq_parms(j) = surveyq_init(j);
  for (j=1; j<=nclass; j++) lognin_parms(j) = lognin_init(j);
    
  for (ifleet=1; ifleet<=nfleet_act; ifleet++)
    for (iyr=1; iyr<=ncatch_f(ifleet); iyr++) f_est(ifleet,iyr) = 0.1;
  recdev.initialize();

  logRbar = theta_parms(1);
  M0 = theta_parms(2);

// =========================================================================================================
PROCEDURE_SECTION
  fobj += square(dummy_datum-dummy_parm);
  
  Set_effort();
  Set_growth();
  Initial_size_structure();
  Set_selectivity();
  Set_survival();
  Update_population(); 
  ObjFunction();

// --------------------------------------------------------------------
FUNCTION Set_effort
  // Convert to Fs
  int count, ifleet, iyear;
  dvariable ratio, ratio_2, delta;

  for (ifleet=1; ifleet<=nfleet_act; ifleet++)
  {
    count = 0;
    for (iyear=styr; iyear<=endyr; iyear++)
    {
      if (effort(ifleet,iyear) > 0)
      {
        if (f_new(ifleet,1) == 0 | iyear < f_new(ifleet,2) | iyear > f_new(ifleet,3))
          { count += 1; f_all(ifleet,iyear) = f_est(ifleet,count); }
        else
         f_all(ifleet,iyear) = -100;
      }  
      else
        f_all(ifleet,iyear) = 0;
    }
  }  

  // Fill in missing values using a ratio estimator:
  for (ifleet=1; ifleet<=nfleet_act; ifleet++)
    if (f_new(ifleet,1) > 0)
    {
     ratio = 0; ratio_2 = 0;
     for (iyear=f_new(ifleet,4); iyear<=f_new(ifleet,5); iyear++)
     {
       if (effort(ifleet,iyear) > 0)
       {
        ratio += -log(1.0-f_all(ifleet,iyear))/effort(ifleet,iyear);
        ratio_2 += 1;
       }
     }
     delta = ratio/ratio_2;
     for (iyear=f_new(ifleet,2); iyear<=f_new(ifleet,3); iyear++)
       f_all(ifleet,iyear) = 1.0-mfexp(-delta*effort(ifleet,iyear));
    }

// --------------------------------------------------------------------
FUNCTION Set_growth
  int iclass, jclass;
  dvariable total;
  
  strans.initialize();

  for (iclass=1; iclass<nclass; iclass++)
  {
    total = (1+mfexp(gtrans_parms(iclass)));
    strans(iclass,iclass) = 1/total;
    strans(iclass,iclass+1) = mfexp(gtrans_parms(iclass))/total;
  }
  
  strans(nclass,nclass) = 1;  // Special case for final diagonal entry.

// --------------------------------------------------------------------
FUNCTION Initial_size_structure
  int iclass;

  N.initialize();
  for (iclass=1;iclass<=nclass;iclass++)
    N(styr,iclass) = mfexp(logRbar)*mfexp(lognin_parms(iclass));

// --------------------------------------------------------------------
FUNCTION Set_selectivity
  int iclass, iyr, isurv, ifleet, ipnt, jpnt;
  dvariable qq, temp, slope_par;
    
  // Produce all selectivities:
  // TODO: Check the ipnt pointer is correct here; inherits 0 from selex_type for fleet 1, could be made to be 1 if required in selex_type setup.
  for (ifleet=1; ifleet<=nselex_pats; ifleet++)
  {
    ipnt = selex_type(ifleet,4);
    if (selex_type(ifleet,2) == 1)
    {
      slope_par = selex_parms(ipnt+2);
      temp = -log(19.0)/slope_par;
      for (iclass=1; iclass<=nclass; iclass++)
       selex_all(ifleet,iclass) = 1.0/(1.0+mfexp(temp*(length(iclass)-selex_parms(ipnt+1))));
      temp =  selex_all(ifleet,nclass);
      for (iclass=1;iclass<=nclass;iclass++) selex_all(ifleet,iclass) /= temp;
    }
    if (selex_type(ifleet,2) == 2)
    {
      for (iclass=1; iclass<=nclass; iclass++)
        selex_all(ifleet,iclass) = 1.0/(1.0+mfexp(selex_parms(ipnt+iclass)));
      temp =  selex_all(ifleet,nclass);
      for (iclass=1; iclass<=nclass; iclass++) selex_all(ifleet,iclass) /= temp;
    }
    if (selex_type(ifleet,2) == 3)
    {
      jpnt = selex_type(selex_type(ifleet,2),4);
      slope_par = selex_parms(jpnt+2);
      temp = -log(19.0)/slope_par;
      for (iclass=1; iclass<=nclass; iclass++)
        selex_all(ifleet,iclass) = 1.0/(1.0+mfexp(temp*(length(iclass)-selex_parms(ipnt+1))));
      temp =  selex_all(ifleet,nclass);
      for (iclass=1; iclass<=nclass; iclass++) selex_all(ifleet,iclass) /= temp;
    }
  } 

  // Fishery and bycatch selectivity
  for (ifleet=1; ifleet<=nfleet_act; ifleet++)
   for (iyr=styr; iyr<=endyr; iyr++)
    {
     ipnt = selex_fleet_pnt(ifleet,iyr);
     for (iclass=1; iclass<=nclass; iclass++)
       selex_fleet(ifleet,iyr,iclass) = selex_all(ipnt,iclass) ;
    }  
  
  // Retention in the pot fishery
  for (ifleet=1; ifleet<=nfleet_ret; ifleet++)
    for (iyr=styr; iyr<=endyr; iyr++)
      for (iclass=1; iclass<=nclass; iclass++)
      {
        ipnt = (reten_fleet_pnt(ifleet,iyr)-1)*nclass;
        reten(iyr,iclass) = (1-hg(iyr))/(1.0+mfexp(reten_parms(ipnt+iclass)));
      } 

  // Survey selectivity
  for (isurv=1; isurv<=nsurvey; isurv++)
   for (iyr=styr; iyr<=endyr+1; iyr++)
    {
     ipnt = surveyq_pnt(isurv,iyr);
     qq = exp(surveyq_parms(ipnt));
     ipnt = selex_survey_pnt(isurv,iyr);
     for (iclass=1; iclass<=nclass; iclass++)
      selex_survey(isurv,iyr,iclass) = qq*selex_all(ipnt,iclass);
    }  
   
  // Nest one survey within another
  for (ipnt=1; ipnt<=nsubsurvey; ipnt++)
   for (iyr=styr; iyr<=endyr+1; iyr++)
    for (iclass=1; iclass<=nclass; iclass++)
     selex_survey(subsurvey(ipnt,1),iyr,iclass) *= selex_survey(subsurvey(ipnt,2),iyr,iclass);

// --------------------------------------------------------------------
FUNCTION Set_survival
  int iyr,iclass,ifleet;

  // Check which fleets this applies to...  

  // Specify natural mortality:
  M = M0;
  for (iyr=styr; iyr<=endyr; iyr++) if (M_pnt(iyr)>1) M(iyr) += Madd_parms(M_pnt(iyr)); 
  
  for (iyr=styr; iyr<=endyr; iyr++)
    for (iclass=1; iclass<=nclass; iclass++)
    {
     S(iyr,iclass) = mfexp(-M(iyr));
     for (ifleet=1; ifleet<=nfleet_act; ifleet++)
      {
       S_fleet(ifleet,iyr,iclass) = (1-selex_fleet(ifleet,iyr,iclass)*f_all(ifleet,iyr));
       exp_rate(ifleet,iyr) = f_all(ifleet,iyr);
       S(iyr,iclass) *= S_fleet(ifleet,iyr,iclass);
      } 
     f_direct(iyr) = selex_fleet(1,iyr,nclass)*f_all(1,iyr); // FIX: This may have to loop over fleet as well?
    }

// --------------------------------------------------------------------
FUNCTION Update_population
  int iyr, iclass, jclass;
  dvariable mbio_out;

  for (iyr=styr; iyr<=endyr; iyr++)
  {
    // Grow individuals for one time-step:
    for (iclass=1; iclass<=nclass; iclass++)
      for (jclass=1; jclass<=nclass; jclass++)
        N(iyr+1,iclass) += strans(jclass,iclass)*N(iyr,jclass)*S(iyr,jclass);
   
    // Add recruitment for next year:
    recruits(iyr) = mfexp(logRbar+recdev(iyr));
    N(iyr+1,1) += recruits(iyr);

    mbio_out = 0;
    for (iclass=1; iclass<=nclass; iclass++) 
      mbio_out += N(iyr,iclass)*fecundity(iclass)*(1-selex_fleet(1,iyr,iclass)*f_all(1,iyr))*exp(-(catch_time(1,iyr)+2/12)*M(iyr));
    mbio(iyr) = mbio_out;
   }

   // TODO: Check why only selex_fleet(1) is used for mbio_calc.
   // TODO: Check 2/12 here in mbio calculation, is this a timing fraction that needs to be generalised?

// ---------------------------------------------------------------------------------------------------------
FUNCTION ObjFunction
  prior_val.initialize(); 
  like_val.initialize();
  Get_Likes();
  Get_Priors();
 // cout << prior_val << endl;
 // cout << like_val << endl;  

// ---------------------------------------------------------------------------------------------------------
FUNCTION Get_Likes
  int ilike=0;
  // Likelihood for Catch biomass (or number)-----------------------
  // This could be re-written withoutiff statement
  for (int ifl=1;ifl<=nfleet;ifl++)
  {
    ilike++; ///< Increment the likelihood index
    if(catch_units(ifl) == 1)
      like_val(ilike) += norm2(log((catch_biom_pred(ifl)+incd)-log(catch_biom_obs(ifl)+incd)));
    else
      like_val(ilike) += norm2(log((catch_num_pred(ifl)+incd)-log(catch_num_obs(ifl)+incd)));
  }
 
  // Catch LFs-----------------------
  for (ifl=1;ifl<=nfleet;ifl++)
  {
    ilike++; ///< Increment the likelihood index
    for (int i=1;i<=nlf_fleet(ifl);i++)
    {
      dvar_vector phat = fleet_lf_pred(ifl,i)/sum(fleet_lf_pred(ifl,i));
      dvector pobs     = fleet_lf_obs(ifl,i)/sum(fleet_lf_obs(ifl,i)); // this should probably be done once in beginning
      // Andre's version waste time w/ constants
      //dvariable Error  = elem_div((phat+Incc),(pobs+Incc));
      // like_val(ilike)  += -ss_fleet_lf(ifl,i)*pobs*log(Error);
      // ignores constant, vector x vector returns a scalar
      like_val(ilike)  += -ss_fleet_lf(ifl,i)*pobs*log(phat);
    } 
  } 

  // Effort indices-----------------------
  /*
  q_effort.initialize();
  for (ifl=1;ifl<=nfleet;ifl++)
  {
    ilike++; ///< Increment the likelihood index
    double nn= 0;
    // TODO: figure out how effort is used
    for (iyr=Yr1;iyr<=endyr;iyr++)
      if (Effort(Ifleet,iyr) > 0) 
      {
        if (FOverWrite(Ifleet,0) == 0 |iyr<FOverWrite(Ifleet,1) | iyr>FOverWrite(Ifleet,2))
        { 
          nn++ ; 
          qEff(Ifleet) += log((Effort(Ifleet,iyr)+Incd)/(ExplRates(Ifleet,iyr)+Incd)); 
        }
      }  
    qEff(Ifleet) = mfexp(qEff(Ifleet)/nn); 
    for (iyr=Yr1;iyr<=endyr;iyr++)
     if (Effort(Ifleet,iyr) > 0)
      if (FOverWrite(Ifleet,0) == 0 |iyr<FOverWrite(Ifleet,1) | iyr>FOverWrite(Ifleet,2))
       like_val(ilike) += square(log((Effort(Ifleet,iyr)+Incd)/(qEff(Ifleet)*(ExplRates(Ifleet,iyr)+Incd))));
   }  
    */

  // Survey indices 
  // !!    SurveyEst(DIfleet,iyr,2) = sqrt(log(square(SurveyEst(DIfleet,iyr,2))+1.0));
  for (int isrv=1;isrv<=nsurvey;isrv++)
  {
    ilike++; ///< Increment the likelihood index
    for (int i=1;i<=nobs_survey(isrv);i++)
    {
      if(survey_units(isrv) == 1)
        like_val(ilike) += 0.5*square(log((survey_biom_obs(isrv,i)+incd)/(survey_biom_pred(isrv,i)+incd))) /(survey_var(isrv,i));
      else 
        like_val(ilike) += 0.5*square(log((survey_num_obs(isrv,i)+incd)/(survey_num_pred(isrv,i)+incd))) /(survey_var(isrv,i));
    }  
  // Survey LF
    ilike++; 
    for (i=1;i<=nlf_survey(isrv);i++)
    {
      dvar_vector phat = survey_lf_pred(isrv,i)/sum(survey_lf_pred(isrv,i));
      dvector pobs     = survey_lf_obs(isrv,i) /sum(survey_lf_obs(isrv,i)); // this should probably be done once in beginning
      like_val(ilike)  -= ss_survey_lf(isrv,i)*pobs*log(phat);
      /* for(Iclass=1;Iclass<=Nclass;Iclass++) if (SurveyObsLF(isrv,Icnt,Iclass) > 0) // Jim says this seems to imply that a zero means no data...UNTRUE{ Error = (PredSurvey(isrv,iyr,Iclass)+Incc)/(SurveyObsLF(isrv,Icnt,Iclass)+Incc); like_val(ilike) += -1*SSSurveyLF(isrv,Icnt)*SurveyObsLF(isrv,Icnt,Iclass)*log(Error); } */
    } 
  } 
                                                    
// ---------------------------------------------------------------------------------------------------------
FUNCTION Get_Priors
  int iprior = 0;
  double nn = 0;
  dvariable mean_F=0;
  // Prior on F-devs 
  /*
  */
  for (int ifl=1;ifl<=nfleet_act;ifl++)
  {
    iprior++;
    mean_F = 0; nn = 0;
    for (iyr=styr;iyr<=endyr;iyr++) 
    {
      if (effort(ifl,iyr) > 0) 
      { 
        mean_F += f_all(ifl,iyr); 
        nn++; 
      }
      mean_F /= nn;
    }
    for (iyr=styr;iyr<=endyr;iyr++) 
      if (effort(ifl,iyr) > 0) 
        prior_val(iprior) += square(f_all(ifl,iyr)-mean_F);
  } 
  iprior++;
  // Prior on Rec Devs
  for (i=styr;i<=endyr;i++) 
  {
    prior_val(iprior) += square(recdev(i));
  }
  iprior++;
    
  // penalties on parameters
  prior_val(iprior) = sum(square(gtrans_parms));
  iprior++;
  for (int i=1;i<=nselex_pars;i++)
    if (selex_phz(i) > 0)
      prior_val(iprior) += square(selex_parms(i));
  iprior++;
  prior_val(iprior) = sum(square(reten_parms));
  iprior++;
  
  // q - prior
  for (int isrv=1;isrv<=nsurveyq_pars;isrv++)
    if (surveyq_psd(isrv) > 0)
      prior_val(iprior) = square(mfexp(surveyq_parms(isrv))-surveyq_pmean(isrv))/(2.0*square(surveyq_psd(isrv)));
  iprior++;
  
  // M-prior
  // prior_val(iprior) = square(M0-MPriorMean)/(2.0*square(MPriorSD));
  // prior_val(iprior) = square(theta-MPriorMean)/(2.0*square(MPriorSD));
  // iprior++;
  // 2nd derivative penalty
  /*
  Penal = 0;
  for (Iselex=1;Iselex<=NSelexPat;Iselex++)
   if (SelexType(Iselex,1) == 2)
    for (Iclass=2;Iclass<=Nclass-1;Iclass++)
     Penal += square(SelexAll(Iselex,Iclass-1)-2.0*SelexAll(Iselex,Iclass)+SelexAll(Iselex,Iclass+1));
  prior_val(iprior) = Penal;   
  */
  
// ---------------------------------------------------------------------------------------------------------
FUNCTION Get_Catch_Pred;
  dvar_vector S1(1,nclass);                              
  dvar_vector N_tmp(1,nclass);                              // Numbers at fishery
  
  fleet_lf_pred.initialize();
  catch_biom_pred.initialize();
  catch_num_pred.initialize();
  N_tmp.initialize();
  
  for (int iyr=styr;iyr<=endyr;iyr++)
  {
    // Need to loop over number of directred fisheries (presently fixed at 1) fleet control matrix
    N_tmp = N(iyr)*mfexp(-catch_time(1,iyr)*M(iyr));
    for (int ifl=1;ifl<=nfleet_act;ifl++)
    {
      S1 = S_fleet(ifl,iyr);
      // Main retained fishery
      if (fleet_control(ifl,2)==1) 
        fleet_lf_pred(ifl,iyr) = elem_prod(N_tmp , elem_prod((1.-S1),reten(iyr)));
      if (fleet_control(ifl, 2)==2) // Discard fishery
        fleet_lf_pred(ifl,iyr) = elem_prod(N_tmp , elem_prod((1.-S1),(1.-reten(iyr))));
      if (fleet_control(ifl, 2)==3) // Main retained fishery
        fleet_lf_pred(ifl,iyr) = elem_prod(N_tmp , (1.-S1));
      N_tmp = elem_prod(N_tmp,S1);
    }
     // Accumulate totals 
     catch_biom_pred(iyr) = fleet_lf_pred(ifl,iyr) * weight;
     catch_num_pred(iyr) = sum(fleet_lf_pred(ifl,iyr) );
  } 

     /*
   for (Iclass=1;Iclass<=Nclass;Iclass++)
    {
     SurvNo = N(iyr,Iclass)*mfexp(-tc(0,iyr)*M(iyr));
     S1 = SF(0,iyr,Iclass);
     CatFleet(0,iyr,Iclass) = SurvNo*(1-S1)*RetCatMale(iyr,Iclass);
     CatFleet(-1,iyr,Iclass) = SurvNo*(1-S1)*(1-RetCatMale(iyr,Iclass));
     SurvNo *= S1;
     for (Ifleet=1;Ifleet<=Nfleet;Ifleet++)
      {
       S2 = SF(Ifleet,iyr,Iclass);
       CatFleet(Ifleet,iyr,Iclass) = SurvNo*(1-S2);
       SurvNo *= S2;
      }
      
     // Accumulate totals 
     for (Ifleet=-1; Ifleet<=Nfleet;Ifleet++)
      {
       CatFleetWghtPred(Ifleet,iyr) += CatFleet(Ifleet,iyr,Iclass) * Wght(Iclass);
       CatFleetNumPred(Ifleet,iyr) += CatFleet(Ifleet,iyr,Iclass);
      } 
      
    }
   
  // Special case for fleet -1
  if (DiscardsOrTotal == 1)
   for (iyr=Yr1;iyr<=endyr;iyr++)
    for (Iclass=1;Iclass<=Nclass;Iclass++)
     CatFleet(-1,iyr,Iclass) = CatFleet(-1,iyr,Iclass) + CatFleet(0,iyr,Iclass);
     */
// ---------------------------------------------------------------------------------------------------------
FUNCTION Get_Survey
  survey_lf_pred.initialize();
  survey_biom_pred.initialize();
  survey_num_pred.initialize();
  for (int isrv=1;isrv<=nsurvey;isrv++)
  {
    for (int i=1;i<=nlf_survey(isrv);i++)
    {
      int iyr                  = yr_survey_lf(isrv,i);
      survey_lf_pred(isrv,i)   = elem_prod(N(iyr),selex_survey(isrv,iyr)); // note use if iyr here...t
      survey_lf_pred(isrv,i)  /= sum(survey_lf_pred(isrv,i));
    }
    for (int i=1;i<=nobs_survey(isrv);i++)
    {
      int iyr                  = yr_survey(isrv,i);
      dvar_vector N_tmp        = elem_prod(N(iyr),selex_survey(isrv,iyr)); // note use if iyr here...t
      survey_biom_pred(isrv,i) = N_tmp * weight;
      survey_num_pred(isrv,i)  = sum(N_tmp);
    }
  }
  /*
    
  PredSurveyNum.initialize();
  PredSurveyWght.initialize();
  for (Isurv=1;Isurv<=Nsurvey;Isurv++)
   for (iyr=Yr1;iyr<=endyr+1;iyr++)
    for (Iclass=1;Iclass<=Nclass;Iclass++)
     {
      PredSurveyWght(Isurv,iyr) += PredSurvey(Isurv,iyr,Iclass)*Wght(Iclass);
      PredSurveyNum(Isurv,iyr) += PredSurvey(Isurv,iyr,Iclass);
     }
  */

// =========================================================================================================
REPORT_SECTION

  check(logRbar);
  check(M);
  check(f_all);
  check(strans);
  check(N);
  check(selex_survey);
  check(selex_fleet);
  check(reten);

  check(S);
  check(S_fleet);
  check(exp_rate);
  check(f_direct);

  check(recruits);
  check(N);
  check(mbio);

  exit(1);
  
// =========================================================================================================

FINAL_SECTION
  // Exit here, to test code up to this point.
  
  // Create final time stamp and determine runtime:
  time(&finish);
  elapsed_time=difftime(finish,start);
  hour=long(elapsed_time)/3600;
  minute=long(elapsed_time)%3600/60;
  second=(long(elapsed_time)%3600)%60;
  
  // Print runtime records to screen:
  cout << endl << endl << "*******************************************"   << endl;
  cout <<         "--Start time: "    <<  ctime(&start)    << endl;
  cout <<          "--Finish time: "    <<   ctime(&finish)    << endl;
  cout <<          "--Runtime: ";
  cout <<  hour <<" hours, "<<minute<<" minutes, "<<second<<" seconds"    << endl;
  cout <<          "*******************************************"  << endl;

// =========================================================================================================

RUNTIME_SECTION
    maximum_function_evaluations 500,1500,2500,25000,25000
    convergence_criteria 0.01,1.e-4,1.e-5,1.e-5