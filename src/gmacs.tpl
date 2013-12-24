// =========================================================================================================
//																			 
// 	Gmacs: Generic size-based Modelling for Alaskan Crab Stocks.
//
// 	Created by Athol Whitten, University of Washington 	
// 	Info: https://github.com/awhitten/gmacs or write to whittena@uw.edu
// 	Copyright (c) 2013. All rights reserved.
//
// 	Acknowledgement: The format for this code, and many of the details,
// 		were adapted from the 'LSMR' model by Steven Martell (2011).
//
// 	TO DO LIST:
//  -Model numbers-at-length on an annual time step, then in the observation
//   submodel, grow and survive numbers-at-length upto the time step samples
//   were collected.  This will require transition matrix for dt and annual
//   transition matrix.
//	
//	- Calculate Reference Points (add routine for this)
//	- Add forecast section (add routine for this)
//  - Add warning section: maybe use macro for warning(object,text)
//  - Add section to write new data file (enable easy labelling after first model attempt)
//
//	=========================================================================================================

GLOBALS_SECTION
	
	#include <admodel.h>
	#include <time.h>
	#include <contrib.h>
	#include <C:/Dropbox/Github/cstar/src/cstar.hpp>

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

	// Open output files using ofstream
	ofstream echoinput("echoinput.gm");
	ofstream warning("warning");

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
	!!version+="Gmacs_V1.00_2013/11/27_by_Athol_Whitten_(UW)_using_ADMB_11.1";
	!!version_short+="Gmacs V1.00";

	!! echoinput << version << endl;
	!! echoinput << ctime(&start) << endl;


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
	init_int verbose;						// display detail to screen (option 1/0)
	init_int final_phase;					// stop estimation after this phase
	init_int use_pin;						// use a .pin file to get initial parameters (option 1/0)
	init_int read_growth;					// read growth transition matrix file (option 1/0)

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
	
	// Read input from main data file:
	
	init_int styr;   	 // start year
	init_int endyr;   	 // end year
	init_number tstep; 	 // time-step

	!! echotxt(styr,  " start year");
	!! echotxt(endyr, " end year");
	!! echotxt(tstep, " time-step");
	
	init_int nsex;		 // number of sexes	
	init_int nfleet;	 // number of fishing fleets
	init_int nsurvey;	 // number of surveys
	init_int nclass;	 // number of size classes
	init_int ndclass;	 // number of size classes (in the data)
	
	init_imatrix class_link(1,nclass,1,2);  // link between data size-classes and model size-classs
	 
	!! echotxt(nsex,    " number of sexes");
	!! echotxt(nfleet,  " number of fleets");
	!! echotxt(nsurvey, " number of surveys")
	!! echotxt(nclass,  " number of size classes");
	!! echotxt(ndclass, " number of size classes for data");
	
	!! echo(class_link);

	init_vector catch_units(-1,nfleet);   			// catch units (pot discards; + other fleets) [1=biomass (tons);2=numbers]
	init_vector catch_multi(-1,nfleet);	  			// additional catch scaling multipliers [1 for no effect]
	init_vector survey_units(1,nsurvey);  			// survey units [1=biomass (tons);2=numbers]
  	init_vector survey_multi(1,nsurvey);  			// additional survey scaling multipliers [1 for no effect]
  	init_int ncatch_obs; 							// number of catch lines to read
	init_int nsurvey_obs;							// number of survey lines to read
	init_number survey_time;                		// time between survey and fishery (for projections)
	
	init_matrix catch_data(1,ncatch_obs,1,4);	 	// catch data matrix, one line per ncatch_obs, requires year, season, fleet, observation
	init_matrix survey_data(1,nsurvey_obs,1,5);	 	// survey data matrix, one line per nsurvey_obs, requires year, season, survey, observation, and error

	// Q: Some pre-processing of these data required. See simple.tpl for example.

  	!! echotxt(catch_units,  " catch units");
	!! echotxt(catch_multi,  " catch multipliers");
	!! echotxt(survey_units, " survey units");
	!! echotxt(survey_multi, " survey multipliers")
	!! echotxt(ncatch_obs,   " number of lines of catch data");
	!! echotxt(nsurvey_obs,  " number of lines of survey data")
	!! echotxt(survey_time,  " time between survey and fishery");
			
	!! echo(catch_data);
	!! echo(survey_data);

	init_vector discard_mort(-1,nfleet);			// discard mortality (per fishery)
	init_vector retention(styr,endyr);				// retention value for each year
	init_matrix catch_time(0,nfleet,styr,endyr);	// timing of each fishery (as fraction of time-step)
	init_matrix effort(0,nfleet,styr,endyr);		// effort by fishery
	init_imatrix f_new(0,nfleet,0,4);				// alternative f estimators (overwrite others)

	// Q: More code for F overwrite (f_new) option needs to be included here. See simple.tpl for example.

	!! echo(discard_mort);
	!! echo(retention);
	!! echo(catch_time);
	!! echo(effort);
	!! echo(f_new);

	init_vector nat_mort(styr,endyr);				// natural mortality pointer
	init_vector mean_length(1,ndclass); 			// mean length vector
	init_vector mean_weight(1,ndclass); 			// mean weight vector
	init_vector fecundity(1,ndclass);				// fecundity vector

	!! echo(nat_mort);
	!! echo(mean_length);
	!! echo(mean_weight);
	!! echo(fecundity);

	init_int lf_flag; 								// length comp data for discard fleet (-1): total catch (1) or  discards (2)
  	
  	!! echotxt(lf_flag,  " length freq data for discard fleet: flag for catch or discards");

	init_int nlf_obs;								// number of length frequency lines to read	
	init_matrix lf_data(1,nlf_obs,1,ndclass+5);		// length frequency data, one line per nlf_obs, requires year, season, fleet, sex, effective sample size, then data vector 

	init_int nlfs_obs;								// number or survey length frequency lines to read
	init_matrix lfs_data(1,nlfs_obs,1,ndclass+5);	// survey length frequency data, one line per nlfs_obs, requires year, season, survey, sex, effective sample size, then data vector

   	!! echotxt(nlf_obs,  " number of length freq lines to read");
  	!! echo(lf_data);

  	!! echotxt(nlfs_obs, " number of survey length freq lines to read");
  	!! echo(lfs_data);
  	
 	init_int ncapture_obs;										// number of capture data lines to read		
 	init_int nmark_obs;											// number of mark data lines to read
 	init_int nrecapture_obs;									// number of recapture data lines to read

	init_matrix capture_data(1,ncapture_obs,1,ndclass+3);		// capture data, one line per ncapture_obs, requires years, fleet, sex, then data vector
	init_matrix mark_data(1,nmark_obs,1,ndclass+3);				// mark data, one line per nmark_obs, requires years, fleet, sex, then data vector
	init_matrix recapture_data(1,nrecapture_obs,1,ndclass+3);	// recapture data, one line per nrecapture_obs, requires years, fleet, sex, then data vector

	!! echotxt(ncapture_obs,   " number of capture data lines");
	!! echotxt(nmark_obs,      " number of mark data lines");
	!! echotxt(nrecapture_obs, " number of recapture data lines")

	// Q: This below should probably go into LOCAL_CALCS.

	!! if(ncapture_obs>0) 
	!! {
		
		!! echo (capture_data);
		!! echo (mark_data);
		!! echo (recapture_data);

	!! }
	
	// Print EOF confirmation to screen and echoinput, warn otherwise:
	init_int eof_data;
	
	!! if(eof_data!=999) {cout << " Error reading main data file \n EOF = "<< eof_data << endl; exit(1);}
	!! cout << " Finished reading main data file \n" << endl;
	!! echotxt(eof_data," EOF: finished reading main data file \n");

	
	//*************************************************************
	// Retain HBC data for now, allow model to run and thus test.
	//*************************************************************

	// Open HBC data file (*.dat) //
	!! ad_comm::change_datafile_name("hbc.dat");
	!! cout << " Reading hbc.dat" << endl;
	
	init_int syr;   	// first year
	init_int nyr;   	// last year
	init_number dt; 	// time-step
	init_int ngear; 	// number of gears
	init_int nbin;		// number of length intervals
	init_vector xbin(1,nbin);  //length-intervals (not mid-points)
	
	int nx;			//number of length bins (nbin-1)
	int nr;			//number of rows in predicted arrays
	!! nr = int((nyr-syr+1)/dt);
	!! nx = nbin;
	vector xmid(1,nbin);
	!! xmid = xbin + 0.5*(xbin(2)-xbin(1));
		
	// Array dimensions //
	init_imatrix dim_array(1,ngear,1,2);
	ivector irow(1,ngear);
	ivector ncol(1,ngear);
	ivector jcol(1,ngear);
	LOC_CALCS
		irow = column(dim_array,1);
		ncol = column(dim_array,2);
		jcol = ncol - 1;
	END_CALCS
	
	// Read in effort data (number of sets) //
	ivector fi_count(1,ngear);
	init_matrix Effort(1,ngear,1,irow);
	vector mean_Effort(1,ngear);
	LOC_CALCS
		/* Calculate mean Effort for each gear, ignore 0*/
		/* number of capture probability deviates fi_count(k) */
		int i,k,n;
		fi_count.initialize();
		for(k=1;k<=ngear;k++)
		{
			n=0;
			for(i=1;i<=irow(k);i++)
			{
				if(Effort(k,i)>0)
				{
					mean_Effort(k) += Effort(k,i);
					n++;
				}
			}
			fi_count(k)     = n;
			mean_Effort(k) /= n;
		}
	END_CALCS
	
	// Read in Capture, Mark, and Recapture arrays //
	init_3darray i_C(1,ngear,1,irow,1,ncol);
	init_3darray i_M(1,ngear,1,irow,1,ncol);
	init_3darray i_R(1,ngear,1,irow,1,ncol);	

	3darray C(1,ngear,1,irow,1,jcol);
	3darray M(1,ngear,1,irow,1,jcol);
	3darray R(1,ngear,1,irow,1,jcol);	

	init_int eof_hbc;
	
	!! if(eof_hbc!=999) {cout << " Error reading hbc data file \n EOF = "<< eof_data << endl; exit(1);}
	!! cout << " Finished reading hbc data file \n" << endl;
	!! echotxt(eof_data," EOF: finished reading hbc data file \n");

// ---------------------------------------------------------------------------------------------------------
// DATA FILE (GROWTH)

	// Q: Make this section conditional on starter file: Must be done inside local calcs.
	// This code requires updating to Gmacs flat format. 

	LOCAL_CALCS

	if(read_growth==1)
	{	

		// Open size transition file (*.dat) //
		!! ad_comm::change_datafile_name(size_trans_file);
		!! cout << " Reading size transition file" << endl;
		!! echoinput << " Start reading size transition file" << endl;
		
		// Read input from growth data file:
		init_int nj;  // number of size intervals
		init_int styr_L;
		init_int endyr_L;
		init_ivector jbin(1,nj);
		init_3darray L(styr_L,endyr_L,1,nj-1,1,nj-1);
		
		// Print EOF confirmation to screen and echoinput, warn otherwise:
		init_int eof_growth;

		!! if(eof_growth!=999) {cout << " Error reading size transition file\n EOF = " << eof_data << endl; exit(1);}
		!! cout << " Finished reading size transition file \n" << endl;
		!! echotxt(eof_growth," EOF: finished reading size transition file \n");

	}

	END_CALCS


// ---------------------------------------------------------------------------------------------------------
// CONTROL FILE

	// Open control file (*.ctl) //
	!! ad_comm::change_datafile_name(control_file);
	!! cout << " Reading control file" << endl;
	!! echoinput << " Start reading control file" << endl;
	
	// Read input from control file:
	init_int npar
	init_matrix theta_control(1,npar,1,7);
	matrix trans_theta_control(1,7,1,npar);
	vector theta_ival(1,npar);
	vector theta_lbnd(1,npar);
	vector theta_ubnd(1,npar);
	ivector theta_phz(1,npar);
	ivector theta_prior(1,npar);
	LOC_CALCS
		trans_theta_control = trans(theta_control);
		theta_ival = trans_theta_control(1);
		theta_lbnd = trans_theta_control(2);
		theta_ubnd = trans_theta_control(3);
		theta_phz  = ivector(trans_theta_control(4));
		theta_prior = ivector(trans_theta_control(5));
	END_CALCS
	
	// Read Selectivity Parms //
	init_ivector sel_type(1,ngear);
	init_ivector sel_phz(1,ngear);
	init_vector lx_ival(1,ngear);
	init_vector gx_ival(1,ngear);
	init_ivector x_nodes(1,ngear);
	init_vector sel_pen1(1,ngear);
	init_vector sel_pen2(1,ngear);
	
	ivector isel_npar(1,ngear);
	
	LOC_CALCS
		/* Determine the number of selectivity parameters to estimate */
		for(k=1;k<=ngear;k++)
		{
			switch(sel_type(k))
			{
				case 1:  // logistic
					isel_npar(k) = 2;
				break;
				case 2:  // eplogis
					isel_npar(k) = 3;
				break;
				case 3:  // linapprox
					isel_npar(k) = x_nodes(k);
				break;
			}
		}
	END_CALCS
	
	init_int nflags;
	init_vector flag(1,nflags);
	// 1) verbose 
	// 2) minimum size of fish for tagging.
	// 3) std of catch residuals in 1st phase
	// 4) std of catch residuals in last phase
	// 5) case switch for type of size transition matrix (0=A, 1=annual, 2=empirical)
	
	// index for minimum size of tagged fish //
	imatrix min_tag_j(1,ngear,1,irow);
	LOC_CALCS
		int j;
		for(k=1;k<=ngear;k++)
		{
			for(i=1;i<=irow(k);i++)
			{
				for(j=1;j<=jcol(k);j++)
				{
					if( M(k)(i,j)>0 || xbin(j)>flag(1) )
					//if( xbin(j)>flag(1) )
					{
						min_tag_j(k,i) = j;
						break;
					}
				}	
			}
		}
	END_CALCS

	// Simulation code: See SM for Details.
	int SimFlag;
	int rseed;
	LOC_CALCS
		SimFlag = 0;
		rseed   = 1;
		int on,opt;
		//the following line checks for the "-SimFlag" command line option
		//if it exists the if statement retreives the random number seed
		//that is required for the simulation model
		if((on=option_match(ad_comm::argc,ad_comm::argv,"-sim",opt))>-1)
		{
			SimFlag = 1;
			rseed   = atoi(ad_comm::argv[on+1]);
			if(SimFlag) cout << "In Simulation Mode\n";
		}
		
	END_CALCS
	
	// Variables for Simulated Data
	vector true_Nt(styr,endyr);
	vector true_Rt(styr,endyr);
	vector true_Tt(styr,endyr);
	matrix true_fi(1,ngear,1,irow);

	// Print EOF confirmation to screen and echoinput, warn otherwise:
	init_int eof_control;

	!! if(eof_control!=999) {cout << " Error reading control file\n EOF = " << eof_control << endl; exit(1);}
	!! cout << " Finished reading control file \n" << endl;
	!! echotxt(eof_data," EOF: finished reading control file \n");

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
	ivector active_parm(1,npar);  //  Pointer from active list to the element of the full parameter list to get label (TODO: ADD THIS)

	// Create dummy datum for use when max phase == 0
	number dummy_datum;
	int dummy_phase;
	!! dummy_datum=1.;
	!! if(final_phase<=0) {dummy_phase=0;} else {dummy_phase=-6;}

	// Adjust the phases to negative if beyond final_phase and find resultant max_phase
	int max_phase;
 
 	LOC_CALCS
  		cout << " Adjust phases \n" << endl;
  		max_phase=1;
  		active_count=0;
  		active_parm(1,npar)=0;
  		par_count=0;
  
		for(i=1;i<=npar;i++)
		{ 
		  	par_count++;
		  	if(theta_phz(i) > final_phase) theta_phz(i)=-1;
		  	if(theta_phz(i) > max_phase) max_phase=theta_phz(i);
		  	if(theta_phz(i) >= 0)
		  	{
		  	  active_count++; active_parm(active_count)=par_count;
		  	}
		}

		active_parms=active_count;
	END_CALCS

	!!cout << "Number of active parameters is " << active_parms << endl;
	!!cout << "Maximum phase for estimation is " << max_phase << endl << endl;

// =========================================================================================================

PARAMETER_SECTION
	init_bounded_number_vector theta(1,npar,theta_lbnd,theta_ubnd,theta_phz);
	number log_ddot_r;
	number log_bar_r;
	number m_infty;

	//Variables for growth.
	number l_infty;
	number vbk;
	number beta;
	
	//Variables for size distribution of new recruits
	number mu_r;
	number cv_r
	
	//Mean fishing mortality rates
	init_vector log_bar_f(1,ngear,-2);
	
	//Overdispersion
	init_vector log_tau(1,ngear,-5);
	
	//Selectivity parameters
	init_bounded_vector_vector sel_par(1,ngear,1,isel_npar,-5.,5.,sel_phz);
	LOC_CALCS
		int k;
		for(k=1;k<=ngear;k++)
		{
			if( sel_type(k)==1 )
			{
				sel_par(k,1) = log(lx_ival(k));
				sel_par(k,2) = log(gx_ival(k));
			}
			if( sel_type(k)==2 )
			{
				sel_par(k,1) = log(lx_ival(k));
				sel_par(k,2) = log(gx_ival(k));
				sel_par(k,3) = -4.0;
			}
		}
	END_CALCS
	
	init_bounded_dev_vector ddot_r_devs(1,nx,-15,15,-2);
	init_bounded_dev_vector bar_r_devs(styr+1,endyr,-15,15,-2);
	!! int phz;
	!! if(flag(4)==1) phz=3; else phz=-3;
	init_bounded_dev_vector l_infty_devs(styr,endyr-1,-5,5,phz);
	
	
	//TODO Fix this so there is a dev vector for each gear, otherwise biased estimates of log_bar_f
	init_bounded_matrix bar_f_devs(1,ngear,1,fi_count,-5.0,5.0,-2);
	
	sdreport_number sd_l_infty;
	
	objective_function_value f;
	
	number m_linf;
	number fpen;
	vector tau(1,ngear);	// over-dispersion parameters >1.0
	vector qk(1,ngear);		// catchability of gear k
	vector mx(1,nx);		// Mortality rate at length xmid
	vector rx(1,nx);		// size pdf for new recruits
	
	vector log_rt(styr+1,endyr);
	matrix fi(1,ngear,1,irow);	// capture probability in period i.
	matrix sx(1,ngear,1,jcol);	// Selectivity at length xmid
	matrix N(styr,endyr,1,nx);		// Numbers(time step, length bins)
	matrix T(styr,endyr,1,nx);		// Marks-at-large (time step, length bins)
	matrix A(1,nx,1,nx);		// Size-transitin matrix (annual step)
	//matrix P(1,nx,1,nx);		// Size-Transition Matrix for step dt
	
	// Predicted observations
	matrix hat_ct(1,ngear,1,irow);			// Predicted total catch
	matrix delta(1,ngear,1,irow);			// residuals in total catch
	3darray Chat(1,ngear,1,irow,1,jcol);	// Predicted catch-at-length
	3darray Mhat(1,ngear,1,irow,1,jcol);	// Predicted new marks-at-length
	3darray Rhat(1,ngear,1,irow,1,jcol);	// Predicted recaptures-at-length
	3darray iP(styr,endyr,1,nx,1,nx);			// Size transition matrix for year i;

	//  Create dummy parameter that will be estimated when final_phase is set to 0
  	init_bounded_number dummy_parm(0,2,dummy_phase)  //  Estimate in phase 0

	
// =========================================================================================================
	
INITIALIZATION_SECTION
	theta     theta_ival;
	log_bar_f -3.5;
	log_tau   1.1;

// =========================================================================================================

PRELIMINARY_CALCS_SECTION

	if(SimFlag)
	{
		cout<<"******************************"<<endl;
		cout<<"**                          **"<<endl;
		cout<<"** Running Simulation Model **"<<endl;
		cout<<"** Random seed = "<<rseed<<"        **"<<endl;
		cout<<"**                          **"<<endl;
		cout<<"******************************"<<endl;
		runSimulationModel(rseed);
	}

// =========================================================================================================

PROCEDURE_SECTION
	if( verbose ) cout<<"\n TOP OF PROCEDURE_SECTION "<<endl;
	fpen.initialize();
	initParameters();  
	calcSurvivalAtLength(); 
	calcSizeTransitionMatrix(); 
	initializeModel();
	calcCaptureProbability();
	calcNumbersAtLength();
	calcSelectivityAtLength();
	calcObservations();
	calc_objective_function();
	sd_l_infty = l_infty;
	if( verbose ) cout<<"\n END OF PROCEDURE_SECTION "<<endl;

//	
FUNCTION void runSimulationModel(const int& seed)
  {
	int i,j,k,im;
	random_number_generator rng(seed);
	
	dvector tmp_ddot_r_devs = value(ddot_r_devs);
	dvector tmp_bar_r_devs  = value(bar_r_devs);
	dmatrix tmp_bar_f_devs  = value(bar_f_devs);
	
	tmp_ddot_r_devs.fill_randn(rng);
	tmp_bar_r_devs.fill_randn(rng);
	tmp_bar_f_devs.fill_randn(rng);
	
	double sig_r = flag(5);
	ddot_r_devs = sig_r*tmp_ddot_r_devs;
	bar_r_devs  = sig_r*tmp_bar_r_devs;
	
	/* Capture probabilities */
	double sig_f = flag(6);
	for(k=1;k<=ngear;k++)
	{
		bar_f_devs(k) = sig_f*tmp_bar_f_devs(k);
	}
	
	initParameters();
	calcSurvivalAtLength();
	calcSizeTransitionMatrix();
	initializeModel();
	calcCaptureProbability();
	calcNumbersAtLength();
	calcSelectivityAtLength();
	calcObservations();
	
	
	/* Overwrite observations and draw from multinomial distribution */
	C=value(Chat);
	M=value(Mhat);
	R=value(Rhat);
	
	for(k=1;k<=ngear;k++)
	{
		for(i=1;i<=irow(k);i++)
		{
			if(Effort(k,i)>0)
			{
				for(j=1;j<=nx;j++)
				{
					if(flag(6))
					{
						C(k)(i)(j) = randnegbinomial(1.e-5+C(k)(i)(j),2.0,rng);
						M(k)(i)(j) = randnegbinomial(1.e-5+M(k)(i)(j),2.0,rng);
						R(k)(i)(j) = randnegbinomial(1.e-5+R(k)(i)(j),2.0,rng);
					}
				}
			}
			
			i_C(k)(i)(2,ncol(k)) = C(k)(i)(1,nx).shift(2);
			i_M(k)(i)(2,ncol(k)) = M(k)(i)(1,nx).shift(2);
			i_R(k)(i)(2,ncol(k)) = R(k)(i)(1,nx).shift(2);
			
		}		
	}
	
	/*Save true data*/
	true_Nt.initialize();
	true_Tt.initialize();
	true_Rt.initialize();
	true_fi = value(fi);
	true_Nt = value(rowsum(N));
	true_Tt = value(rowsum(T));
	for(i=styr;i<=endyr;i++)
	{
		if(i==styr) true_Rt(i) = value(mfexp(log_ddot_r+ddot_r_devs(nx)));
		else       true_Rt(i) = value(mfexp(log_rt(i)));
	}
	
  }
//
FUNCTION initParameters
  {
	/* Leading parameters */
	log_ddot_r = theta(1);
	log_bar_r  = theta(2);	
	m_infty    = theta(3);
	l_infty    = theta(4);
	vbk        = theta(5);
	beta       = theta(6);
	mu_r       = theta(7);
	cv_r       = theta(8);
  }
//
FUNCTION calcSizeTransitionMatrix
  {
	/*
	This function calls the necessary routines to compute the Size Transition Matrix (P)
	*/
	int t,im;
	dvariable linf;
	switch(int(flag(4)))
	{
		case 0:
			A = calcLTM(xmid,l_infty,vbk,beta);
			for(t=styr;t<endyr;t++)
			{
				iP(t) = A;
			}
		break;
		//
		case 1:
			if(!active(l_infty_devs))
			{
				A = calcLTM(xmid,l_infty,vbk,beta);
			}
			else
			for(t=styr;t<endyr;t++)
			{
				if(active(l_infty_devs))
				{
					linf = l_infty*exp(l_infty_devs(t));
					A = calcLTM(xmid,linf,vbk,beta);
				}
				iP(t) = A;
			}
		break;
		//
		case 2: // use externally estimated Size transition matrices 
			for(t=styr;t<endyr;t++)
			{
				im = t;
				if(t < styr_L) im = styr_L;
				if(t > endyr_L) im = endyr_L;
				iP(t) = L(im);
			}
		break;
	}
	
	
  }
//
FUNCTION initializeModel
  {
	int i,ii,k,ik;
	//Set up the initial states.
	N.initialize();
	T.initialize();
	
	
	/* Initialize numbers at length at the first time step. */
	dvar_vector init_r(1,nx);
	dvar_matrix phi_X(1,nx,1,nx);
	dvariable a=1/(cv_r*cv_r);  //a=1/cv^2
	dvariable b=mu_r/a;		  //b=mu/a
	rx  = dgamma(xmid,a,b);
	rx /= sum(rx);
	
	/* Calculate per-recruit survivorship at length */
	phi_X(1) = rx;
	ii = 0;
	for(i=2;i<=nx;i++)
	{
		phi_X(i) = elem_prod(phi_X(i-1),mfexp(-mx)) * iP(styr);
		if( i==nx )
		{
			phi_X(i) = phi_X(i) + elem_div(phi_X(i),1.-mfexp(-mx));
		}
	}
	
	/* Initial numbers at length */
	init_r = mfexp(log_ddot_r + ddot_r_devs);
	N(styr)   = init_r * phi_X;
	
	/* Annual recruitment */
	log_rt = log_bar_r + bar_r_devs;
  }
//
FUNCTION calcCaptureProbability		
  {
	/* Catchability */
	qk         = elem_div(mfexp(log_bar_f),mean_Effort);
	
	/* Capture probability at each time step. */
	int i,k;
	ivector ik(1,ngear);
	ik = 1;
	fi.initialize();
	
	for(k=1;k<=ngear;k++)
	{
		for(i=1;i<=irow(k);i++)
		{
			if( Effort(k,i)>0 )
			{
				fi(k,i) = qk(k)*Effort(k,i)*mfexp(bar_f_devs(k)(ik(k)++));
			}
		}
	}
	
  }
//
FUNCTION calcSurvivalAtLength
  {
	/*
	This function calculates the length-specific survival rate
	based on the Lorenzen function, where survival increases
	with increasing length.
	
	mortality rate at length x  mx=m.linf*linf/xbin
	note that m_linf is an annual rate.
	*/
	mx = m_infty * l_infty/xmid;
  }
//
FUNCTION calcSelectivityAtLength
  {
	/*
	This function calculates the length-specific selectivity.
	The parametric option is a logistic curve (plogis(x,lx,gx))
	*/
	int k;
	double dx;
	dvariable p1,p2,p3;
	sx.initialize();
	Selex cSelex;
	dmatrix xi(1,ngear,1,x_nodes);
	dvar_matrix yi(1,ngear,1,x_nodes);
	
	/*
	dvariable gamma = 0.1;
	dvariable x1 = 30.0;
	dvariable x2 = 49.0;
	cout<<cSelex.eplogis(xmid,x1,x2,gamma)<<endl;
	dvector x = ("{5, 10, 15, 20, 25, 30, 35, 40, 45, 50}");
	dvar_vector y = ("{0.03, 0.16, 0.50, 0.84, 0.97, 0.99, 1.00, 1.00, 1.00, 1.00}");
	cout<<"Linear interpolation"<<endl;	
	cout<<cSelex.linapprox(x,y,xmid)<<endl;
	*/
	
	for(k=1;k<=ngear;k++)
	{
		switch(sel_type(k))
		{
			case 1:  //logistic
				p1 = mfexp(sel_par(k,1));
				p2 = mfexp(sel_par(k,2));
				sx(k) = log( cSelex.logistic(xmid,p1,p2) );
			break;
			case 2: //eplogis
				p1 = mfexp(sel_par(k,1));
				p2 = mfexp(sel_par(k,2));
				p3 = mfexp(sel_par(k,3))/(1.+mfexp(sel_par(k,3)));
				sx(k) = log( cSelex.eplogis(xmid,p1,p2,p3) );
			break;
			case 3: //linapprox
				dx = (double(nbin)-1.)/(double(x_nodes(k)-1.));
				xi(k).fill_seqadd( min(xmid),dx );
				yi(k)= sel_par(k);
				sx(k) = cSelex.linapprox(xi(k),yi(k),xmid);
			break;
		}
		sx(k) = mfexp( sx(k) - log( mean( mfexp(sx(k))+1.e-30 ) ) );
	}
  }
//
FUNCTION calcNumbersAtLength
  {
	/*	This function updates the numbers at length
		at the start of each year as a function of the 
		numbers at length times the survival rate * size transition
		and add new recuits-at-length.
		
	  	N_{t+1} = elem_prod(N_{t},mfexp(-mx*dt)) * P + rt*rx
	
	  	These are the total number of fish (tagged + untagged)
		at large in the population.  N is used in the observation
		models to determine number of captures and recaptures is
		based on T.
		
		The function also does the accounting for the predicted number
		of marked individuals at large (T).
		
		t = index for year
	*/
	
	
	int i,k,t;
	i = 0;
	dvariable rt;
	dvector mt(1,nx);
	for(t=styr;t<endyr;t++)
	{
		/* TOTAL NUMBERS AT LARGE */
		rt     = mfexp(log_rt(t+1));
		N(t+1) = elem_prod(N(t),mfexp(-mx)) * iP(t) + rt*rx;
		
		/* MARKED NUMBERS AT LARGE */
		i++;
		mt = 0;
		for(k=1;k<=ngear;k++)
		{
			mt += M(k)(i);
		}
		T(t+1) = elem_prod(T(t) + mt,mfexp(-mx)) * iP(t);
	}
	
	if( verbose==2 ) cout<<"Nt\n"<<rowsum(N)<<endl;
	if( verbose==2 ) cout<<"Tt\n"<<rowsum(T)<<endl;
  }
//
FUNCTION calcObservations
  {
	/*
		Calculate the predicted total catch-at-length (Chat)
		Calculate the predicted total recaptures-at-length (Rhat)
		Calculate the predicted total new markes released-at-length (Mhat)
		
		t   = index for year
		its = index for time step
		k   = index for gear
		
		TRYING A SIMPLE DISCRETE MODEL FOR OBSERVATIONS.
	*/
	
	int t,its,k,i,lb;
	Chat.initialize();
	Mhat.initialize();
	Rhat.initialize();
	
	
	dvar_vector Ntmp(1,nx);
	dvar_vector Ttmp(1,nx);
	dvar_vector Utmp(1,nx);
	dvar_vector Mtmp(1,nx);
	dvar_vector zx(1,nx);
	dvar_vector ox(1,nx);
	dvar_vector ux(1,nx);
	
	i=0;
	zx = mx*dt;
	ox = elem_div(1.0-mfexp(-zx),zx);
	
	for(t=styr;t<=endyr;t++)
	{
		Ntmp = N(t);
		Ttmp = T(t);
		Utmp = Ntmp-Ttmp;//posfun(Ntmp - Ttmp,0.01,fpen);
		Mtmp.initialize();
		i++;
		for(k=1;k<=ngear;k++)
		{
			
			if( Effort(k,i)>0 )
			{
				ux           = 1.0 - mfexp(-fi(k,i)*sx(k));
				Chat(k)(i)   = elem_prod(ux,Ntmp);
				Mhat(k)(i)   = elem_prod(ux,Utmp);
				Rhat(k)(i)   = elem_prod(ux,Ttmp);
			}
			//if( Effort(k,i)>0 )
			//{
			//	lb           = min_tag_j(k,i);
			//	ux           = 1.0 - mfexp(-fi(k,i)*sx(k));
			//	Chat(k)(i)   = elem_prod(ux,elem_prod(Ntmp,ox));
			//	Mhat(k)(i)(lb,nx)   = elem_prod(ux,elem_prod(Utmp,ox))(lb,nx);
			//	Rhat(k)(i)   = elem_prod(ux,elem_prod(Ttmp,ox));
			//	Mtmp(lb,nx) += Mhat(k)(i)(lb,nx);
			//}
		}
		
		/* Survive and grow tags-at-large and add new tags */
		//if( t < endyr )
		//{
		//	T(t+1) = elem_prod(T(t),mfexp(-mx*dt))*iP(t) + Mtmp;
		//}
	}
	
	if( verbose==2 ) cout<<"Tt\n"<<rowsum(T)<<endl;
  }
//
FUNCTION calc_objective_function;
  {
	int i,j,k;
	/* PENALTIES TO ENSURE REGULAR SOLUTION */
	dvar_vector pvec(1,4);
	pvec.initialize();
	if(!last_phase())
	{
		pvec(1) = dnorm(first_difference(ddot_r_devs),0,0.2);
		pvec(1)+= norm2(ddot_r_devs);
		pvec(2) = dnorm(bar_r_devs,0,0.4);
		for(k=1;k<=ngear;k++)
		{
			dvariable mean_f = sum(fi(k))/fi_count(k);
			pvec(3) += dnorm(mean_f,0.1,0.01);
			pvec(4) += dnorm(bar_f_devs(k),0,1.0);
		}
	}
	else
	{
		pvec(1) = dnorm(first_difference(ddot_r_devs),0,0.4);
		pvec(1)+= norm2(ddot_r_devs);
		pvec(2) = dnorm(bar_r_devs,0,0.6);
		for(k=1;k<=ngear;k++)
		{
			dvariable mean_f = sum(fi(k))/fi_count(k);
			pvec(3) += dnorm(mean_f,0.1,2.5);
			pvec(4) += dnorm(bar_f_devs(k),0,1.0);
		}
		
		//pvec(3) = dnorm(log_bar_f,log(0.1108032),2.5);
	}
	if( verbose ) cout<<"Average fi = "<<mfexp(log_bar_f)<<endl;
	
	
	/* PENALTIES TO INSURE DEV VECTORS HAVE A MEAN O */
	dvar_vector dev_pen(1,ngear);
	for(k=1;k<=ngear;k++)
	{
		dvariable s = mean(bar_f_devs(k)); 
		dev_pen(k)  = 1.e7 * s*s;
	}
	
	/* LIKELIHOODS */
	/*
		fvec(1) = likelihood of the total catch-at-length.
		fvec(2) = likelihood of the total marks-at-length.
		fvec(3) = likelihood of the total recap-at-length.
	*/
	
	dvar_vector fvec(1,4);
	fvec.initialize();
	double tiny = 1.e-10;
	tau = mfexp(log_tau)+1.01;
	
	for(k=1;k<=ngear;k++)
	{
		for(i=1;i<=irow(k);i++)
		{
			if( Effort(k,i)>0 )
			{
				for(j=1;j<=nx;j++)
				{
					if(active(log_tau))
					{
						fvec(1) -= log_negbinomial_density(C(k)(i)(j),Chat(k)(i)(j)+tiny,tau(k));
						fvec(2) -= log_negbinomial_density(M(k)(i)(j),Mhat(k)(i)(j)+tiny,tau(k));
						fvec(3) -= log_negbinomial_density(R(k)(i)(j),Rhat(k)(i)(j)+tiny,tau(k));
					} 
					else
					{
						fvec(1) += square(C(k)(i)(j)-Chat(k)(i)(j));
						fvec(2) += square(M(k)(i)(j)-Mhat(k)(i)(j));
						fvec(3) += square(R(k)(i)(j)-Rhat(k)(i)(j));
					}
				}
			}
		}
	}
	
	if(active(l_infty_devs))
	{
		fvec(4) = dnorm(l_infty_devs,0,0.2);
	}
	/*
	PRIORS for estimated model parameters from the control file.
	*/
	dvar_vector priors(1,npar);
	priors.initialize();
	dvariable ptmp; 
	for(i=1;i<=npar;i++)
	{
		if(active(theta(i)))
		{
			switch(theta_prior(i))
			{
			case 1:		//normal
				ptmp=dnorm(theta(i),theta_control(i,6),theta_control(i,7));
				break;
				
			case 2:		//lognormal CHANGED RF found an error in dlnorm prior. rev 116
				ptmp=dlnorm(theta(i),theta_control(i,6),theta_control(i,7));
				break;
				
			case 3:		//beta distribution (0-1 scale)
				double lb,ub;
				lb=theta_lbnd(i);
				ub=theta_ubnd(i);
				ptmp=dbeta((theta(i)-lb)/(ub-lb),theta_control(i,6),theta_control(i,7));
				break;
				
			case 4:		//gamma distribution
				ptmp=dgamma(theta(i),theta_control(i,6),theta_control(i,7));
				break;
				
			default:	//uniform density
				ptmp=-log(1./(theta_control(i,3)-theta_control(i,2)));
				break;
			}
			priors(i)=ptmp;	
		}
	}
	
	/*
	PENALTIES FOR SELECTIVITY COEFFICIENTS
	*/
	dvar_vector sel_pen(1,ngear);
	sel_pen.initialize();
	for(k=1;k<=ngear;k++)
	{
		if( sel_type(k)==3 )
		{
			sel_pen(k) = sel_pen1(k)/nx * norm2(first_difference(first_difference(sx(k))));
			for(j=1;j<nx;j++)
			{
				if(sx(k,j+1)<sx(k,j))
					sel_pen(k) += sel_pen2(k) * square(sx(k,j+1)-sx(k,j));
			}
		}
	}
	
	if( verbose ) cout<<"Fvec\t"<<setprecision(4)<<fvec<<endl;
	if(fpen > 0) cout<<"Fpen = "<<fpen<<endl;
	f  = sum(fvec); 
	//f += sum(pvec); 
	//f += sum(priors); 
	//f += sum(dev_pen); 
	//f += sum(sel_pen); 
	f += 1.e5*fpen;
  }
//
FUNCTION dvar_matrix calcLTM(dvector& x, const dvariable &linf, const dvariable &k, const dvariable &beta)
  {
	/*This function computes the length transition matrix.*/
	/*
	- x is the mid points of the length interval vector.
	
	- cumd_gamma(x,a) is the same as Igamma(a,x) in R.
	- If length interval > linf, then assume now further growth.
	- Note the use of posfun to ensure differentiable.
	*/
	RETURN_ARRAYS_INCREMENT();
	int i,j;
	double dx;
	double bw = 0.5*(x(2)-x(1));
	int n = size_count(x);     //number of length intervals
	dvar_vector alpha(1,n);
	dvar_matrix P(1,n,1,n);
	P.initialize();
	
	//Growth increment
	dvar_vector dl(1,n);
	for(j=1;j<=n;j++)
	{
		dl(j) = log(mfexp( (linf-x(j))*(1.-mfexp(-k)) )+1.0);
	}
	alpha = dl/beta;
	
	/* Size transition probability */
	for(i=1;i<=n;i++)
	{
		dvar_vector t1(i,n);
		for(j=i;j<=n;j++)
		{
			dx = x(j)-x(i);
			P(i)(j) = cumd_gamma(dx+bw,alpha(i)) - cumd_gamma(dx-bw,alpha(i));
			//cout<<j<<" "<<x(i)<<" "<<x(j)<<" "<<P(i)(j)<<endl;
		}
		//P(i)(i,n-1) = first_difference(t1);
		P(i) /= sum(P(i));
	}
	RETURN_ARRAYS_DECREMENT();
	//cout<<P<<endl;
	return(P);
  }

// =========================================================================================================

REPORT_SECTION
	int i,j,im;
	REPORT(f          );
	REPORT(log_ddot_r );
	REPORT(log_bar_r  );
	REPORT(m_infty    );
	REPORT(l_infty    );
	REPORT(vbk        );
	REPORT(beta       );
	REPORT(mu_r       );
	REPORT(cv_r       );
	REPORT(log_bar_f  );
	REPORT(tau        );
	
	ivector yr(styr,endyr);
	yr.fill_seqadd(styr,1);
	REPORT(yr);
	REPORT(ngear);
	REPORT(irow);
	REPORT(jcol);
	REPORT(xmid);
	REPORT(mx);
	REPORT(sx);
	
	REPORT(delta);
	
	dvector Nt = value(rowsum(N));
	dvector Tt = value(rowsum(T));
	dvector Rt(styr,endyr);
	for(i=styr;i<=endyr;i++)
	{
		if(i==styr) Rt(i) = value(mfexp(log_ddot_r+ddot_r_devs(nx)));
		else       Rt(i) = value(mfexp(log_rt(i)));
	}
	REPORT(Nt);
	REPORT(Tt);
	REPORT(Rt);
	
	REPORT(log_rt);
	REPORT(fi);
	REPORT(Effort);
	REPORT(bar_f_devs);
	
	REPORT(N);
	REPORT(T);
	REPORT(i_C);
	REPORT(i_M);
	REPORT(i_R);
	REPORT(Chat);
	REPORT(Mhat);
	REPORT(Rhat);
	REPORT(A);
	if(SimFlag)
	{
		REPORT(true_Nt);
		REPORT(true_Rt);
		REPORT(true_Tt);
		REPORT(true_fi);
	}

// =========================================================================================================

FINAL_SECTION
	
	// Create final time stamp and determing runtime:
	time(&finish);
	elapsed_time=difftime(finish,start);
	hour=long(elapsed_time)/3600;
	minute=long(elapsed_time)%3600/60;
	second=(long(elapsed_time)%3600)%60;
	
	// Print runtime records to screen:
	cout << endl << endl << "*******************************************" 	<< endl;
	cout << 				"--Start time: "		<<	ctime(&start)		<< endl;
	cout <<					"--Finish time: "		<< 	ctime(&finish)		<< endl;
	cout <<					"--Runtime: ";
	cout <<	hour <<" hours, "<<minute<<" minutes, "<<second<<" seconds"		<< endl;
	cout <<					"*******************************************"	<< endl;

// =========================================================================================================

RUNTIME_SECTION
    maximum_function_evaluations 500,1500,2500,25000,25000
    convergence_criteria 0.01,1.e-4,1.e-5,1.e-5