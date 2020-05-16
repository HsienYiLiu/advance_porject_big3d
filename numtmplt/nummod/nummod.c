/*********************************************************
  nummod.c
  -------------------
copyright : (C) 2006 by Ryan Brenke and Philip Yang Shen
email : rbrenke@bu.edu yangshen@bu.edu
 *********************************************************/

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <getopt.h>
#include <time.h>

#include _MOL_INCLUDE_

#define PI 3.14159265

void print_short_args (char* app_name);
void print_help_args (char* app_name);
void print_args (char* app_name);
void my_rotate_atomgrp (struct atomgrp* prot, struct atomgrp* rotprot, struct rmatrix* rmatrix, struct tvector* center_of_rotation);
void perturb_atomgrp (struct atomgrp* ag, struct atomgrp* moved_ag, double translate_rangei, double rotate_range, struct tvector* center_of_rotation);
double cal_energy(struct atomgrp* agA, struct atomgrp* agB,struct prms* prms);
struct tvector* cal_gradients(struct atomgrp* agA, struct atomgrp* agB,struct prms* prms);
double cal_distance(struct atomgrp* agA, struct atomgrp* agB, int atomi, int atomj);
struct tvector* check_gradients(struct atomgrp* agA, struct atomgrp* agB,struct prms* prms, double delta);
void moving_along_center(struct atomgrp* agA,struct atomgrp* agB,struct prms* prms);
double Cal_PT_MC();
double Cal_MIN_CV();
double b2_formula(double x);
void mmc_moving_protein(struct atomgrp* agA, struct atomgrp* agB,struct prms* prms);
#define MAXSLEN 200
char* ATOM_PRM_FILE;

int main (int argc, char* argv[])
{
	char* app_name = argv[0];
	if (argc < 2)
	{
		print_short_args (app_name);
		print_help_args (app_name);
		exit (EXIT_FAILURE);
	}

	char* rec_ifile; // input file
	char* lig_ifile; // input file
	//char* ofile = (char*) mymalloc (MAXSLEN * sizeof (char));
	ATOM_PRM_FILE = atom_prm_file (ATOM_PRM);


	size_t slen; // string length

	int c;
	while (1)
	{

		c = getopt (argc, argv, "hp:");
		if (c == -1)
			break;
		switch (c)
		{
			case 'h':
				print_args (app_name);
				return 0;
			case 'p':
				slen = strlen (optarg);
				if (slen > MAXSLEN)
				{
					fprintf (stderr, "atom parameter file name %s is too long\n", optarg);
					exit (EXIT_FAILURE);
				}
				ATOM_PRM_FILE = optarg;
				break;
			default:
				break;
		}
	}

	if (optind+1 < argc)
	{
		rec_ifile = argv[optind];
		optind++;
		lig_ifile = argv[optind];
		optind++;
		while (optind < argc)
		{
			printf ("ignored argument: %s\n", argv[optind]);
			optind++;
		}
	}
	else
	{
		print_short_args (app_name);
		print_help_args (app_name);
		exit (EXIT_FAILURE);
	}


	struct prms* prms = read_prms (ATOM_PRM_FILE, _MOL_VERSION_);
	//Read receptor and ligand structure
	struct atomgrp* agA = read_file_atomgrp (rec_ifile, prms);
	struct atomgrp* agB = read_file_atomgrp (lig_ifile, prms);

    printf("\n");
	printf("Q1-e: Tabulate the values of electrostatic energy while moving one of the protein along center of mass\n");
    printf("Showing the 1-e results\n");
    moving_along_center(agA, agB, prms);
	printf("\n");
	printf("Q2-c: Write Metropolis Monte Carlo search for two proteins.\n");
	printf("Showing the 2-c results first\n");
	mmc_moving_protein(agA,agB,prms);
	printf("Output 2-c result as 10 files, using pymol to see the result...\n");
	printf("\n");
	struct tvector* temp_tv = (struct tvector*) mymalloc (sizeof (struct tvector));
    struct tvector* com_A = center_of_mass(agA);
    struct tvector* com_B = center_of_mass(agB);
	// Code for 1-a
	temp_tv->X = 0.5*(com_A->X - com_B->X);
	temp_tv->Y = 0.5*(com_A->Y - com_B->Y);
	temp_tv->Z = 0.5*(com_A->Z - com_B->Z);
	struct atomgrp* agA_moved = copy_atomgrp(agA);
	translate_atomgrp (agA_moved, agA_moved,temp_tv); // translate agA 
	char* current_ofile = (char*) mymalloc (100 * sizeof (char)); 
	sprintf (current_ofile, "1-a.ms");
	fprint_file_atomgrp(current_ofile, agA_moved, prms);
	cal_gradients(agA,agB, prms);
	check_gradients(agA,agB, prms,0.001);
	Cal_PT_MC();
    Cal_MIN_CV();
	return EXIT_SUCCESS;
}
//2-c
void mmc_moving_protein(struct atomgrp* agA, struct atomgrp* agB,struct prms* prms){
    struct tvector* com_A = center_of_mass(agA);
    struct atomgrp* atgroup_min;
    double min = 1000;
    double temp;
    double  kt = 1;
    int i = 0;
    
    while(i < 1001){
		com_A = center_of_mass(agA);
		double ori = complex_energy(agA, agB, prms);
		// rotational and trans atmo group
		struct atomgrp* agA_moved = copy_atomgrp(agA);
		perturb_atomgrp(agA, agA_moved, 2, PI/18, com_A);
		temp = complex_energy(agA_moved, agB, prms); - ori;
		if(complex_energy(agA_moved, agB, prms); < ori){
			agA = agA_moved; 
				//find min
		}else{
			if(complex_energy(agA_moved, agB, prms) < min){
				min = complex_energy(agA_moved, agB, prms);
				atgroup_min = agA_moved;
				printf("2-C is running and find the new min with --> %lf\n",min);
			}  
			double p = (double)rand()/RAND_MAX*1-0;
				if(p < exp(-(temp/kt))){
				    agA = agA_moved; 
				}else{
				    agA = agA;
				}
		}
		free(com_A);
	i++;
    }
    //return temp_tv;
}
//2-b
double Cal_MIN_CV(){
    double min = 1000;
    double min_x;
    //double upper = 0.5;
    //double lower = -0.5;
    double temp,x_next;
    double kt = 1;
    double x = -4.0; 
    int i = 0;
    while(i < 10001){
        double delta = ((double)rand()/RAND_MAX*2.0-1.0)/10;
	x_next = x + delta;
	temp = b2_formula(x_next) - b2_formula(x);

	if(temp < 0){
	    x = x_next;
	}else{
            // find min
            if(b2_formula(x_next) < min){
                min = b2_formula(x_next);
	        min_x = x_next;
	    }
            double p = (double)rand()/RAND_MAX*1-0;
	    if(p < exp(-(temp/kt))){
	        x = x_next;
	    }else{
	        x = x;
	    }
	}
	kt = kt - 0.00001;
	i++;
    }  
    printf("Answer of 2-b Min energy: %f, Last value of x: %f\n", min, min_x);
    return x;
}
double b2_formula(double x){
    return (((-0.5)*pow(x,2)) - (0.5*x) - 0.3)*exp(-fabs(x) + 0.01*pow(x,2));
}
//2-a
double Cal_PT_MC(){
    //Generating 1000 points(x,y)
    struct tvector* temp_tv = (struct tvector*) mymalloc (sizeof (struct tvector));
    double total_point_inside = 0;
    for(int i = 0; i < 1001; i++){
	temp_tv[i].X = (double)(rand())/((RAND_MAX+1.0));
	temp_tv[i].Y = (double)(rand())/((RAND_MAX+1.0));
	if(sqrt(pow(temp_tv[i].X,2) + pow(temp_tv[i].X,2) <= 1)){
	    total_point_inside++;
	}
    }
    double pi = total_point_inside/1000.0;
    printf("Answer of 2-a, Total points inside: %d, PI: %f\n",(int)total_point_inside, pi*4);
    return pi*4;
}
// 1-e 
void moving_along_center(struct atomgrp* agA,struct atomgrp* agB,struct prms* prms){
    struct tvector* temp_tv = (struct tvector*) mymalloc (sizeof (struct tvector));
    struct tvector* com_A = center_of_mass(agA);
    struct tvector* com_B = center_of_mass(agB);
    double energy = 0.0;
    //temp_tv->X = 0.5*(com_A->X - com_B->X);
    //temp_tv->Y = 0.5*(com_A->Y - com_B->Y);
    //temp_tv->Z = 0.5*(com_A->Z - com_B->Z);
    //struct atomgrp* agA_moved = copy_atomgrp(agA);
    //translate_atomgrp (agA_moved, agA_moved,temp_tv); // translate agA 
    // cal energy
    // for loop for each step's distance
    double temp_distance = sqrt(pow(com_A->X - com_B->X,2)+pow(com_A->Y - com_B->Y,2)+pow(com_A->Z - com_B->Z,2));
    for(int i = -20; i < 21; i++){
	temp_tv->X = (i/temp_distance)*(com_A->X - com_B->X);
        temp_tv->Y = (i/temp_distance)*(com_A->Y - com_B->Y);
        temp_tv->Z = (i/temp_distance)*(com_A->Z - com_B->Z);
        struct atomgrp* agA_moved = copy_atomgrp(agA);
        translate_atomgrp (agA_moved, agA_moved,temp_tv);
        energy = cal_energy(agA_moved,agB,prms);
        printf("Moving Step: %d,  Energy: %.4f\n",i,energy);

    }
}
// 1-d,fourth question - check C
struct tvector* check_gradients(struct atomgrp* agA, struct atomgrp* agB,struct prms* prms, double delta){
    struct tvector* temp_tv = (struct tvector*) mymalloc (sizeof (struct tvector)*agA->natoms);
    int i = 0;
    int j = 0;
    double temp = 0;
    double eng_x = 0;
    double eng_y = 0;
    double eng_z = 0;
    double tempX = 0;
    double tempY = 0;
    double tempZ = 0;
    for(i = 0; i < agA -> natoms; i++){
	tempX = 0;
        tempY = 0;
	tempZ = 0;
        for(j = 0; j < agB -> natoms; j++){
            // cal R 
            double X = agA->atoms[i].X - agB->atoms[j].X;
            double Y = agA->atoms[i].Y - agB->atoms[j].Y;
            double Z = agA->atoms[i].Z - agB->atoms[j].Z;
            double R = cal_distance(agA,agB,i,j);
            double X_del_D  = sqrt(pow(X+delta,2)+pow(Y,2)+pow(Z,2));
            double Y_del_D  = sqrt(pow(X,2)+pow(Y+delta,2)+pow(Z,2));
            double Z_del_D  = sqrt(pow(X,2)+pow(Y,2)+pow(Z+delta,2));

            temp = (prms -> chrgs[agA -> atoms[i].atom_typen])*(prms -> chrgs[agB -> atoms[j].atom_typen])/R;
            
            eng_x = (prms -> chrgs[agA -> atoms[i].atom_typen])*(prms -> chrgs[agB -> atoms[j].atom_typen])/X_del_D;
            eng_y = (prms -> chrgs[agA -> atoms[i].atom_typen])*(prms -> chrgs[agB -> atoms[j].atom_typen])/Y_del_D;
            eng_z = (prms -> chrgs[agA -> atoms[i].atom_typen])*(prms -> chrgs[agB -> atoms[j].atom_typen])/Z_del_D;

	    tempX += (temp - eng_x)/delta;
            tempY += (temp - eng_y)/delta;
	    tempZ += (temp - eng_z)/delta;
            
        }

        temp_tv[i].X = tempX;
        temp_tv[i].Y = tempY;
        temp_tv[i].Z = tempZ; 
	if(i < 10){
            printf("Answer of 1-d --> Checking the output of cal gradients:  %f, %f, %f \n", tempX, tempY , tempZ );
        }
    }
    free(agA);
    free(agB);
    //printf("Output of cal gradients %f, %f, %f",a,b,c);
    return temp_tv;
}

// 1-c - cal gradients
struct tvector* cal_gradients(struct atomgrp* agA, struct atomgrp* agB,struct prms* prms){
    struct tvector* temp_tv = (struct tvector*) mymalloc (sizeof (struct tvector)*agA->natoms);
    int i = 0;
    int j = 0;
    double a = 0;
    double b = 0;
    double c = 0;
    for(i = 0; i < agA -> natoms; i++){
	a = 0;
	b = 0;
	c = 0;
        for(j = 0; j < agB -> natoms; j++){
	    // cal R 
            double X = agA->atoms[i].X - agB->atoms[j].X; 
            double Y = agA->atoms[i].Y - agB->atoms[j].Y;
            double Z = agA->atoms[i].Z - agB->atoms[j].Z;
            double R = pow(cal_distance(agA,agB,i,j),3);
	    a += (prms -> chrgs[agA -> atoms[i].atom_typen])*(prms -> chrgs[agB -> atoms[j].atom_typen])*X/R;
	    b += (prms -> chrgs[agA -> atoms[i].atom_typen])*(prms -> chrgs[agB -> atoms[j].atom_typen])*Y/R;
	    c += (prms -> chrgs[agA -> atoms[i].atom_typen])*(prms -> chrgs[agB -> atoms[j].atom_typen])*Z/R;
			    
	}
	temp_tv[i].X = a;
	temp_tv[i].Y = b;
	temp_tv[i].Z = c;
	if(i < 10){
            printf("Answer of 1-c --> Output of cal gradients %f, %f, %f \n",a,b,c);
        }
    }
    //printf("Output of cal gradients %f, %f, %f",a,b,c);
    return temp_tv;
}

double cal_distance(struct atomgrp* agA, struct atomgrp* agB, int atomi, int atomj){
    double X = agA->atoms[atomi].X - agB->atoms[atomj].X; 
    double Y = agA->atoms[atomi].Y - agB->atoms[atomj].Y;
    double Z = agA->atoms[atomi].Z - agB->atoms[atomj].Z;
    double R = sqrt(pow(X,2)+pow(Y,2)+pow(Z,2));
    return R; 
}
// 1-b - calculate energy
double cal_energy(struct atomgrp* agA, struct atomgrp* agB,struct prms* prms){
    double total_energy = 0;
    int i = 0;
    int j = 0;
    for(i = 0; i < agA -> natoms; i++){
        for(j = 0; j < agB -> natoms; j++){
            total_energy += (prms -> chrgs[agA -> atoms[i].atom_typen])*(prms -> chrgs[agB -> atoms[j].atom_typen])/cal_distance(agA,agB,i,j);
	}
    }
    return total_energy;
}
void print_help_args (char* app_name)
{
	fprintf (stderr, "try '%s -h' for a list of arguments\n", app_name);
}

void print_short_args (char* app_name)
{
	fprintf (stderr, "usage: %s [arguments] RECEPTOR LIGAND\n", app_name);
	fprintf (stderr, "print correlation energy of RECEPTOR and LIGAND\n");
}

void print_args (char* app_name)
{
	print_short_args (app_name);

	printf ("\n");
	printf ("arguments:\n");
	printf ("   %-20s Use <atom.prm> as atom parameter file (default: %s)\n", "-p <atom.prm>", ATOM_PRM_FILE);
}

void my_rotate_atomgrp (struct atomgrp* prot, struct atomgrp* rotprot, struct rmatrix* rmatrix, struct tvector* center_of_rotation)
{
	int atomi;
	for (atomi = 0; atomi < prot->natoms; atomi++)
	{
		float X = prot->atoms[atomi].X;
		float Y = prot->atoms[atomi].Y;
		float Z = prot->atoms[atomi].Z;
		rotprot->atoms[atomi].X = rmatrix->a11*(X - center_of_rotation->X) + rmatrix->a12*(Y - center_of_rotation->Y) + rmatrix->a13*(Z - center_of_rotation->Z) + center_of_rotation->X;
		rotprot->atoms[atomi].Y = rmatrix->a21*(X - center_of_rotation->X) + rmatrix->a22*(Y - center_of_rotation->Y) + rmatrix->a23*(Z - center_of_rotation->Z) + center_of_rotation->Y;
		rotprot->atoms[atomi].Z = rmatrix->a31*(X - center_of_rotation->X) + rmatrix->a32*(Y - center_of_rotation->Y) + rmatrix->a33*(Z - center_of_rotation->Z) + center_of_rotation->Z;
	}
}

void perturb_atomgrp (struct atomgrp* ag, struct atomgrp* moved_ag, double translate_range, double rotate_range, struct tvector* center_of_rotation)
{
	struct tvector* temp_tv = (struct tvector*) mymalloc (sizeof (struct tvector));
	struct rmatrix* temp_rmatrix = (struct rmatrix*) mymalloc (sizeof (struct rmatrix));

	double qw,qx,qy,qz; //quaternions
	double r,theta,phi; //intermediate spherical coordinates for uniform sampling

	if(translate_range<0.0)
	{
		printf ("Input error: translational range should be NONNEGATIVE\n");
		exit (EXIT_FAILURE);
		//printf ("Notice: translational range is forced to be ZERO.\n");
		//translate_range=0;	    
	}
	if(rotate_range<0.0)
	{
		printf ("Input error: rotational range should be NONNEGATIVE\n");
		exit (EXIT_FAILURE);
		//printf ("Notice: rotational range is forced to be ZERO.\n");
		//rotate_range=0;
	}
	else
		if(rotate_range>PI)
		{
			printf ("Input error: maximum rotational range should be PI\n");
			exit (EXIT_FAILURE);
			//printf ("Notice: rotational range is forced to be PI.\n");	    
			//rotate_range=PI;
		}


	//translational perturbation
	/*Uniform sampling in a sphere of radius translate_range*/
	/* intermediate spherical coordinates (r,theta,phi) */

	//random number generator: to modify


	r = translate_range * pow((rand() / ((double)RAND_MAX + 1)),1/3.0);
	phi = acos(1-2*(rand() / ((double)RAND_MAX + 1)));
	theta = 2*PI*(rand() / ((double)RAND_MAX + 1));

	temp_tv->X = r * cos(theta) * sin(phi);
	temp_tv->Y = r * sin(theta) * sin(phi);
	temp_tv->Z = r * cos(phi);


	//rotational perturbation
	//Kuffner paper describes how to generate uniform unit quaternions
	//global uniform sampling: max range PI
	//to modify if need ``local'' orietational perturbation
	//uniform sampling in a sphere of exponential coordinates
	//essential: space of exponential coordinates is similar to the Euclidean space of translations

	r = rotate_range * pow((rand() / ((double)RAND_MAX + 1)),1/3.0);
	phi = acos(1-2*(rand() / ((double)RAND_MAX + 1)));
	theta = 2*PI*(rand() / ((double)RAND_MAX + 1));

	//transform into quaternions
	qw = cos(r/2);
	qx = sin(r/2) * cos(theta) * sin(phi);
	qy = sin(r/2) * sin(theta) * sin(phi);
	qz = sin(r/2) * cos(phi);

	//generate rotation matrix
	temp_rmatrix->a11 = 1 - 2 * (pow(qy,2) + pow(qz,2));
	temp_rmatrix->a12 = 2 * (qx*qy - qz*qw);
	temp_rmatrix->a13 = 2 * (qx*qz + qy*qw);

	temp_rmatrix->a21 = 2 * (qx*qy + qz*qw);
	temp_rmatrix->a22 = 1 - 2 * (pow(qx,2) + pow(qz,2));
	temp_rmatrix->a23 = 2 * (qy*qz - qx*qw);

	temp_rmatrix->a31 = 2 * (qx*qz - qy*qw);
	temp_rmatrix->a32 = 2 * (qy*qz + qx*qw);
	temp_rmatrix->a33 = 1 - 2 * (pow(qx,2) + pow(qy,2));

	my_rotate_atomgrp (ag, moved_ag, temp_rmatrix, center_of_rotation);
	translate_atomgrp (moved_ag, moved_ag, temp_tv);
}