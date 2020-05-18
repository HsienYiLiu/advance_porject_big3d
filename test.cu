#include "device_launch_parameters.h"
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <time.h>
#include <sys/time.h>
#include <string.h>
#define EXIT_FAILURE 1
#define X 0
#define Y 1
#define Z 2
#define MAX_INT   2147483647 
//typedef enum { FALSE, TRUE } bool;

#define DIM 3                  /* Dimension of points */
typedef int    tPointi[DIM];   /* Type integer point */
typedef double tPointd[DIM];   /* Type double point */
#define PMAX 1000000             /* Max # of pts */
typedef enum boolean{ FALSE, TRUE } boolean;
tPointd Vertices[PMAX];        /* All the points */
tPointi Faces[PMAX];           /* Each triangle face is 3 indices */
tPointd com_Vertices[PMAX];
tPointi com_Faces[PMAX];
int check = 0;
tPointi Box[PMAX][2];          /* Box around each face */
int n_facets, n_vertices;      /* Original polyhedron*/
int com_facets, com_vertices,counter;  /* Original polyhedron*/
int final[PMAX];

void read_ori(void);
void read_com(void);
int ComputeBox( int F, tPointd bmin, tPointd bmax );
int irint( double x );
__device__ char BoxTest ( int n, tPointd a, tPointd b, tPointi Box );
__device__ int InBox( tPointd q, tPointd bmin, tPointd bmax );
void RandomRay( tPointd ray, int radius );
void AddVec( tPointd q, tPointd ray );
int InPolyhedron(int index, int F,int n, tPointd q, tPointd bmin, tPointd bmax, int radius );
#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true)
{
   if (code != cudaSuccess) 
   {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}
int main(){
    int n, F, i;
    tPointd q, bmin, bmax;
    int radius;
    read_ori();
    read_com();
    n = n_vertices;
    F = n_facets;
    // Allocate memory
    for ( i = 0; i < DIM; i++ ){
        bmin[i] = bmax[i] = Vertices[0][i];
    }
    radius = ComputeBox( n, bmin, bmax );
    counter = com_vertices - 1;
    while( counter >= 0 ) {
        int index = com_vertices - counter - 1;
        q[X] = com_Vertices[counter][X];
        q[Y] = com_Vertices[counter][Y];
        q[Z] = com_Vertices[counter][Z];
        printf( "\n %d -------->q = %lf %lf %lf\n", counter, q[X], q[Y], q[Z] );
        printf( "In = %d\n", InPolyhedron( index , F,n, q, bmin, bmax, radius ) );
        counter--;
    }
    // check segment
    
    
    return 0;
}
__device__ double Dot( tPointd a, tPointd b )
{
    int i;
    double sum = 0.0;
    for( i = 0; i < DIM; i++ )
       sum += a[i] * b[i];

    return  sum;
}
__device__ int PlaneCoeff(tPointd N)
{
    int i;
    double t;              /* Temp storage */
    double biggest = 0.0;  /* Largest component of normal vector. */
    int m = 0;             /* Index of largest component. */


    /* Find the largest component of N. */
    for ( i = 0; i < DIM; i++ ) {
      t = fabs( N[i] );
      if ( t > biggest ) {
        biggest = t;
        m = i;
      }
    }
    return m;
}
__device__ int SegPlaneInt(double D,double denom, double num, tPointd q, tPointd r)
{
    double t;
    
    //printf("SegPlaneInt: num=%lf, denom=%lf\n", q[0], q[1] );

    if ( denom == 0.0 ) {  /* Segment is parallel to plane. */
       if ( num == 0.0 )   /* q is on plane. */
           return 5;
       else
           return 0;
    }
    else
       t = num / denom;
    //printf("SegPlaneInt: t=%lf \n", t );
    
    /*for( i = 0; i < DIM; i++ ){
       p[i] = q[i] + t * ( r[i] - q[i] );
    }*/

    if ( (0.0 < t) && (t < 1.0) )
         //return '1';
         return 9;
    else if ( num == 0.0 )   //t == 0 
         return 6;
    else if ( num == denom ) //t == 1 
         return 7;
    else return 8;
}
__device__ int AreaSign( tPointd a, tPointd b, tPointd c )  
{
    double area2;

    area2 = ( b[0] - a[0] ) * ( c[1] - a[1] ) -
            ( c[0] - a[0] ) * ( b[1] - a[1] );

    /* The area should be an integer. */
    if      ( area2 >  0.5 ) return  1;
    else if ( area2 < -0.5 ) return -1;
    else                     return  0;
} 
__device__ int InTri2D( int area0, int area1, int area2 )
{
   /* compute three AreaSign() values for pp w.r.t. each edge of the face in 2D */

   if ( ( area0 == 0 ) && ( area1 > 0 ) && ( area2 > 0 ) ||
        ( area1 == 0 ) && ( area0 > 0 ) && ( area2 > 0 ) ||
        ( area2 == 0 ) && ( area0 > 0 ) && ( area1 > 0 ) ) 
     return 2;

   if ( ( area0 == 0 ) && ( area1 < 0 ) && ( area2 < 0 ) ||
        ( area1 == 0 ) && ( area0 < 0 ) && ( area2 < 0 ) ||
        ( area2 == 0 ) && ( area0 < 0 ) && ( area1 < 0 ) )
     return 2;                 
   
   if ( ( area0 >  0 ) && ( area1 > 0 ) && ( area2 > 0 ) ||
        ( area0 <  0 ) && ( area1 < 0 ) && ( area2 < 0 ) )
     return 3;

   if ( ( area0 == 0 ) && ( area1 == 0 ) && ( area2 == 0 ) )
     //printf( "Error in InTriD\n" ); exit(EXIT_FAILURE);
     return -3;    

   if ( ( area0 == 0 ) && ( area1 == 0 ) ||
        ( area0 == 0 ) && ( area2 == 0 ) ||
        ( area1 == 0 ) && ( area2 == 0 ) )
     return 1;

   else  
     return 4;  
}
__device__ int VolumeSign( tPointd a, tPointd b, tPointd c, tPointd d )
{ 
   double vol;
   double ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz;
   double bxdx, bydy, bzdz, cxdx, cydy, czdz;

   ax = a[X];
   ay = a[Y];
   az = a[Z];
   bx = b[X];
   by = b[Y];
   bz = b[Z];
   cx = c[X]; 
   cy = c[Y];
   cz = c[Z];
   dx = d[X];
   dy = d[Y];
   dz = d[Z];
   //printf("%lf, %lf, %lf, %lf, %lf, %lf, %lf, %lf, %lf, %lf \n",ax,ay,az,bx,by,bz,cx,cy,cz,dx);

   bxdx=bx-dx;
   bydy=by-dy;
   bzdz=bz-dz;
   cxdx=cx-dx;
   cydy=cy-dy;
   czdz=cz-dz;
   vol =   (az-dz) * (bxdx*cydy - bydy*cxdx)
         + (ay-dy) * (bzdz*cxdx - bxdx*czdz)
         + (ax-dx) * (bydy*czdz - bzdz*cydy);


   /* The volume should be an integer. */
   if      ( vol > 0.5 )   return  1;
   else if ( vol < -0.5 )  return -1;
   else                    return  0;
}
__device__ int SegTriCross(int vol0, int vol1, int vol2)
{
   
 
   //printf( "SegTriCross:  vol0 = %d; vol1 = %d; vol2 = %d\n", vol0, vol1, vol2 ); 
     
   /* Same sign: segment intersects interior of triangle. */
   if ( ( ( vol0 > 0 ) && ( vol1 > 0 ) && ( vol2 > 0 ) ) || 
        ( ( vol0 < 0 ) && ( vol1 < 0 ) && ( vol2 < 0 ) ) )
      return 33;
   
   /* Opposite sign: no intersection between segment and triangle */
   if ( ( ( vol0 > 0 ) || ( vol1 > 0 ) || ( vol2 > 0 ) ) &&
        ( ( vol0 < 0 ) || ( vol1 < 0 ) || ( vol2 < 0 ) ) )
      return 0;

   else if ( ( vol0 == 0 ) && ( vol1 == 0 ) && ( vol2 == 0 ) )
     //fprintf( stderr, "Error 1 in SegTriCross\n" ), exit(EXIT_FAILURE);
     return -3;   
 
   /* Two zeros: segment intersects vertex. */
   else if ( ( ( vol0 == 0 ) && ( vol1 == 0 ) ) || 
             ( ( vol0 == 0 ) && ( vol2 == 0 ) ) || 
             ( ( vol1 == 0 ) && ( vol2 == 0 ) ) )
      return 11;

   /* One zero: segment intersects edge. */
   else if ( ( vol0 == 0 ) || ( vol1 == 0 ) || ( vol2 == 0 ) )
      return 22;
   
   else
     return -3;
     //fprintf( stderr, "Error 2 in SegTriCross\n" ), exit(EXIT_FAILURE);
}
__global__ void check_each( tPointd * bmin, tPointd * bmax,int radius, tPointd * c_com_V,int F,tPointi * ori_F,tPointd * ori_V,tPointd * r,tPointd * q, tPointi *Box, int * out)
{
      
      volatile __shared__ bool FoundIt;
      // initialize shared status
      FoundIt = false;
      __syncthreads();
      int k = 0, crossings = 0;
      int code = -1; 
      //int i = blockIdx.x;
      int i = blockIdx.x;
      //printf("i %d \n",i);
      crossings = 0;
      // get N
      tPointd N,rq;
      //printf("q qqqqqq %lf, %lf, %lf\n",q[0][X],q[0][Y],q[0][Z]);
      N[X] = (ori_V[ori_F[i][Z]][Z]- ori_V[ori_F[i][X]][Z])*(ori_V[ori_F[i][Y]][Y]-ori_V[ori_F[i][X]][Y])-(ori_V[ori_F[i][Y]][Z]- ori_V[ori_F[i][X]][Z])*(ori_V[ori_F[i][Z]][Y]- ori_V[ori_F[i][X]][Y]);
      N[Y] = (ori_V[ori_F[i][Y]][Z]- ori_V[ori_F[i][X]][Z])*(ori_V[ori_F[i][Z]][Y]- ori_V[ori_F[i][X]][Z])-(ori_V[ori_F[i][Y]][X]- ori_V[ori_F[i][X]][X])*(ori_V[ori_F[i][Z]][Y]- ori_V[ori_F[i][X]][Y]);
      N[Z] = (ori_V[ori_F[i][Y]][X]- ori_V[ori_F[i][X]][X])*(ori_V[ori_F[i][Z]][Y]- ori_V[ori_F[i][X]][Y])-(ori_V[ori_F[i][Y]][Y]- ori_V[ori_F[i][X]][Y])*(ori_V[ori_F[i][Z]][X]- ori_V[ori_F[i][X]][X]);
      // Cal dot
      double D,num,denom;
      D = Dot( ori_V[ori_F[i][0]], N );
      int m;
      m = PlaneCoeff(N);
      num = D - Dot( *q, N );
      rq[X] = r[0][X] - q[0][X];
      rq[Y] = r[0][Y] - q[0][Y];
      rq[Z] = r[0][Z] - q[0][Z];
      denom = Dot(rq,N);
      int tmp_code = SegPlaneInt(D, denom, num, *q, *r);
      //double t = num / denom;

      //printf("SegPlaneInt: %d\n", tmp_code );      
      //printf("bmax: %lf,%lf,%lf\n", bmax[0][0],bmax[0][1],bmax[0][2] );      
      //f = &Box[0][0][0];
      //tmp_code = 1;
      if(i < F){
         if ( !InBox( *q, *bmin, *bmax ) == 2 ){
              out[i] = 0;
              FoundIt = true;
              //printf("wpwowow %d\n", out[i]);
         }
         /*if (BoxTest( i, *q, *r, *Box ) == '0' && FoundIt == false) {
              
              out[i] = 0;
              FoundIt = true;
              printf("BoxTest = 0!\n");
         }else */
         if(FoundIt == false){
             if(tmp_code == 8){
                 tmp_code = 8;
                 //FoundIt == true;
             }
             if(tmp_code == 6){
                 tPointd pp,Tp[3];     // projected T: three new vertices 
                 //t = num / denom;
                 
                 // Project out coordinate m in both p and the triangular face 
                 int j = 0;
                 for ( i = 0; i < DIM; i++ ) {
                     if ( i != m ) {    //skip largest coordinate 
                         pp[j] = q[0][i];
                         for ( k = 0; k < 3; k++ ){
	                     Tp[k][j] = ori_V[ori_F[i][k]][i];
                             //printf(" plane=(%lf)\n", Tp[k][j]);
                         }
                         j++;
                          
                      }
                 }
                 int area0 = AreaSign( pp, Tp[0], Tp[1] );
                 int area1 = AreaSign( pp, Tp[1], Tp[2] );
                 int area2 = AreaSign( pp, Tp[2], Tp[0] );                 
                 tmp_code = InTri2D(  area0, area1, area2 );
                 //FoundIt == true;
                 //printf("areaaa %d\n", out[i]);
                 //code = InTri2D( Tp, pp );
             }
             else if(tmp_code == 7){
                 tPointd pp,Tp[3];     // projected T: three new vertices 
                 //t = num / denom;

                 // Project out coordinate m in both p and the triangular face 
                 int j = 0;
                 for ( i = 0; i < DIM; i++ ) {
                     if ( i != m ) {    //skip largest coordinate 
                         pp[j] = r[0][i];
                         for ( k = 0; k < 3; k++ ){
                             Tp[k][j] = ori_V[ori_F[i][k]][i];
                             //printf(" plane=(%lf)\n", Tp[k][j]);
                         }
                         j++;

                      }
                 }
                 int area0 = AreaSign( pp, Tp[0], Tp[1] );
                 int area1 = AreaSign( pp, Tp[1], Tp[2] );
                 int area2 = AreaSign( pp, Tp[2], Tp[0] );
                 tmp_code = InTri2D(  area0, area1, area2 );
                 //FoundIt == true;
                 //printf("areaaa %d\n", out[i]);
                 //code = InTri2D( Tp, pp );
             //}else if(tmp_code == 10){
                 //out[i] = 10;
                 //FoundIt == true;
             }else if(tmp_code == 9){
                 int vol0, vol1, vol2;
                 vol0 = VolumeSign( q[0], ori_V[ori_F[i][0] ], ori_V[ori_F[i][1] ], r[0] );
                 vol1 = VolumeSign( q[0], ori_V[ori_F[i][1] ], ori_V[ori_F[i][2] ], r[0] );
                 vol2 = VolumeSign( q[0], ori_V[ori_F[i][2] ], ori_V[ori_F[i][0] ], r[0] );
                 //printf( "SegTriCross:  vol0 = %d; vol1 = %d; vol2 = %d\n", vol0, vol1, vol2 ); 
                 tmp_code = SegTriCross(vol0,vol1,vol2);
                 //FoundIt = true;

             }else{
                 tmp_code = tmp_code;
         
             }
         }
         if(FoundIt == false){
           code = tmp_code;
           //code = 10;
           printf( "Face = %d: BoxTest/SegTriInt returns %d\n\n", i, code ); 
          
           //If ray is degenerate, then goto outer while to generate another.
           //if ( code == 10 || code == 2 || code == 3 ) {
           if( code == 5 || code == 11 || code == 22){
              printf("Degenerate ray\n");
              //out[i] = -3;
              //crossing++;
              FoundIt = true;  
              //printf("out %d\n",out[i]);
           }
         
           //If ray hits face at interior point, increment crossings.
           else if ( code == 33) {
              crossings++;
              //printf( "crossings = %d\n", crossings );
           }

           //If query endpoint q sits on a V/E/F, return that code.
           else if ( code == 2 || code == 3|| code == 1)
              //return code;
              out[i] = code;

           //If ray misses triangle, do nothing. 
           else if ( code == 44 || code == 8|| code == 8 )
              ;

           else{
              out[i] = -3;
           } 
              //fprintf( stderr, "Error, exit(EXIT_FAILURE)\n" ), exit(1);      
         }
         //if( ( crossings % 2 ) == 1 )
            //out[i] = 1;
         out[i] = crossings;
         printf("check if every point is check i -> %d, out -> %d \n",i,out[i]);
         }
}

int InPolyhedron(int index, int F,int n, tPointd q, tPointd bmin, tPointd bmax, int radius )
{
    tPointd r;  /* Intersection point; not used. */
    int k = 0;
    tPointd *d_bmin, *d_bmax, *c_com_V,*ori_V,*final_r,*final_q;
    tPointi *cu_box,*ori_F;
    int *out,*result;
    //char result[counter];
    result = (int *)malloc(sizeof(int)*F);
    gpuErrchk(cudaMalloc(&c_com_V,sizeof(tPointd)*F));
    cudaMalloc(&ori_V,sizeof(tPointd)*n);
    cudaMalloc(&ori_F,sizeof(tPointi)*F);
    cudaMalloc(&d_bmax,sizeof(tPointd)*3);
    cudaMalloc(&d_bmin,sizeof(tPointd)*3);
    cudaMalloc(&final_r,sizeof(tPointd)*3);
    cudaMalloc(&final_q,sizeof(tPointd)*3); 
    cudaMalloc(&cu_box,sizeof(tPointi)*2*F);
    cudaMalloc(&out,sizeof(tPointi)*F);

    cudaMemcpy(c_com_V, com_Vertices, sizeof(tPointd)*F, cudaMemcpyHostToDevice);
    cudaMemcpy(ori_V, Vertices, sizeof(tPointd)*n, cudaMemcpyHostToDevice);
    cudaMemcpy(ori_F, Faces, sizeof(tPointi)*F, cudaMemcpyHostToDevice);
    cudaMemcpy(d_bmin, bmin, sizeof(tPointd)*DIM, cudaMemcpyHostToDevice);
    cudaMemcpy(d_bmax, bmax, sizeof(tPointd)*DIM, cudaMemcpyHostToDevice);
    cudaMemcpy(final_q, q, sizeof(tPointd)*3, cudaMemcpyHostToDevice);
    cudaMemcpy(cu_box, Box, sizeof(tPointi)*2*F, cudaMemcpyHostToDevice);
    cudaMemcpy(out, result, sizeof(int)*F, cudaMemcpyHostToDevice);

    //printf("Box test %d\n",cu_box[0][0][0]);
   
   //LOOP:
    while( k++ < F) {
      //crossings = 0;
  
      RandomRay( r, radius ); 
      AddVec( q, r ); // add the ray with the point to create end point
      
      printf("Ray endpoint: (%lf,%lf,%lf)\n", r[0],r[1],r[2] );
      cudaMemcpy(final_r, r, sizeof(tPointd)*3, cudaMemcpyHostToDevice);
      check_each<<<F, 1>>>(d_bmin,d_bmax,radius,c_com_V,F,ori_F, ori_V,final_r,final_q,cu_box, out);     
      cudaMemcpy(result,out, sizeof(int)*F, cudaMemcpyDeviceToHost);
      //printf("RRResult %d\n",k);   
      break;

   } 
   // check result
   int final_result = 0; 
   for(int c = 0; c < counter; c++){
       final_result = final_result + result[c];
   }
   if(final_result % 2 == 1){
       final_result = 1;
   }else{
       final_result = 0;
   }
   //printf("testt final %d\n", index);
   free(result);
   cudaFree(d_bmin);cudaFree(d_bmax);cudaFree(c_com_V);
   cudaFree(ori_F);cudaFree(ori_V);cudaFree(final_r);
   cudaFree(final_q);cudaFree(out);cudaFree(cu_box);
   return final_result;
}
__device__ int InBox( tPointd q, tPointd bmin, tPointd bmax )
{
  //printf("baxxxx test %lf, %lf, %lf\n", q[Z],bmax[Z],q[X]);
  if( ( bmin[X] <= q[X] ) && ( q[X] <= bmax[X] ) &&
      ( bmin[Y] <= q[Y] ) && ( q[Y] <= bmax[Y] ) &&
      ( bmin[Z] <= q[Z] ) && ( q[Z] <= bmax[Z] ) ){
    //printf("TRUEEEE");
    return 1;
   
  }
  return 2;
}
/* Return a random ray endpoint */
 void RandomRay( tPointd ray, int radius )
{
  double x, y, z, w, t;
  /* Generate a random point on a sphere of radius 1. */
  /* the sphere is sliced at z, and a random point at angle t
     generated on the circle of intersection. */
  z = 2.0 * (double) rand() / MAX_INT - 1.0;
  t = 2.0 * M_PI * (double) rand() / MAX_INT;
  //printf("check %lf\n",rand1);
  w = sqrt( 1 - z*z );
  x = w * cos( t );
  y = w * sin( t );
  
  ray[X] = radius * x;
  ray[Y] = radius * y;
  ray[Z] = radius * z;
  
  /*printf( "RandomRay returns %6d %6d %6d\n", ray[X], ray[Y], ray[Z] );*/
}
void AddVec( tPointd q, tPointd ray )
{
  int i;
  
  for( i = 0; i < DIM; i++ )
    ray[i] = q[i] + ray[i];
}
__device__ char BoxTest ( int n, tPointd a, tPointd b, tPointi Box)
{
   int i; /* Coordinate index */
   int w;
   //printf(" Box %d\n", Box[0][0][0]);
   for ( i=0; i < DIM; i++ ) {
       w = Box[n]; //min: lower left 
       if ( ((int)a[i] < w ) && ((int)b[i] < w) ) return '0';
       w = Box[n]; // max: upper right 
       if ( ((int)a[i] > w) && ((int)b[i] > w) ) return '0';
   }
   return '?';
}
__global__ void cal(tPointd *bmin, tPointd *bmax,tPointd *V,int F){

    int i = blockIdx.x; // will give you X block Index at that particular thread
    int j = blockIdx.y; // will give you Y block Index at that particular thread. 
    if(i < F){
        //j = j%3;
        for(j = 0; j < 3; j++){
            if( V[i][j] < *bmin[j] )
                *bmin[j] = V[i][j];
            if( V[i][j] > *bmax[j] ){
                *bmax[j] = V[i][j];
                //printf("V %lf\n",V[i][j]);
            }
 //           printf("Check i = %d, j = %d, F = %d\n",i,j,F);
        }
    }
   // printf("bmax %lf, bmin %lf \n",*bmax[Y],*bmin[Y]);
}
int ComputeBox( int n, tPointd bmin, tPointd bmax ){
  double radius;
  tPointd *min, *max,*d_bmax, *d_bmin, *d_a;
  min = (tPointd *)malloc(sizeof(tPointd)*DIM); // Allocate array2 on host 
  max = (tPointd *)malloc(sizeof(tPointd)*DIM); // Allocate array2 on host 

  cudaMalloc(&d_a,sizeof(tPointd)*n);
  cudaMalloc(&d_bmax,sizeof(tPointd)*3);
  cudaMalloc(&d_bmin,sizeof(tPointd)*3);

  cudaMemcpy(d_a, Vertices, sizeof(tPointd)*n, cudaMemcpyHostToDevice);
  cudaMemcpy(d_bmin, bmin, sizeof(tPointd)*DIM, cudaMemcpyHostToDevice);
  cudaMemcpy(d_bmax, bmax, sizeof(tPointd)*DIM, cudaMemcpyHostToDevice);

  //dim3 blockSize(256);
  //dim3 gridSize((n + blockSize.x) / blockSize.x);
  cal<<<n+1, 1>>>(d_bmin, d_bmax, d_a, n);
  cudaMemcpy(max,d_bmax, sizeof(tPointd)*DIM, cudaMemcpyDeviceToHost);
  cudaMemcpy(min,d_bmin, sizeof(tPointd)*DIM, cudaMemcpyDeviceToHost);
  printf("------------------------\n");
  printf("bmax %lf bmin %lf \n",*max[X],*min[X]);
  printf("bmax %lf, bmin %lf \n",*max[Y],*min[Y]);
  printf("bmax %lf, bmin %lf \n",*max[Z],*min[Z]);
  radius = sqrt( pow( (double)(*max[X] - *min[X]), 2.0 ) +
                 pow( (double)(*max[Y] - *min[Y]), 2.0 ) +
                 pow( (double)(*max[Z] - *min[Z]), 2.0 ) );
  printf("radius = %lf\n", radius);
  bmax[0] = *max[0];bmax[1] = *max[1];bmax[2] = *max[2];
  bmin[0] = *min[0];bmin[1] = *min[1];bmin[2] = *min[2];
  
  //printf("radius = %lf\n", bmax[2]);
  cudaFree(d_bmax);
  cudaFree(d_bmin);
  cudaFree(d_a);
  free(max);
  free(min);

  return irint( radius +1 ) + 1;
}

int irint( double x )
{
        return (int) rint( x );
}
void read_ori(void)
{
    FILE * fp;
    char * line = NULL;
    size_t len = 0;
    ssize_t read;
    int count = 0;
    //float a,b,c;
    fp = fopen("b.off", "r");
    int i = 0;
    int j,k,w;

    if (fp == NULL)
        exit(EXIT_FAILURE);
    while ((read = getline(&line, &len, fp)) != -1) {
        count++;
        char *token = strtok(line, " ");
        int token_count = 0;
        while (token != NULL ) {
            // init facets and vertices
            if(count <= 2){
                if(token_count == 0){
                    n_vertices = atoi(token);
                }else if(token_count == 1){
                    n_facets = atoi(token);
                }
                token_count++;
            }else if(count > 3 && count <  n_vertices + 4){
                if(token_count == 0){
                    Vertices[count - 4][X] = atof(token);
                }else if(token_count == 1){
                    Vertices[count - 4][Y] = atof(token);
                }else{
                    Vertices[count - 4][Z] = atof(token);
                }
                token_count++;
            } else if(count >= n_vertices + 4){
                i = count - n_vertices - 4;

                if(token_count == 1){
                    Faces[i][X] = atoi(token);
                }else if(token_count == 2){
                    Faces[i][Y] = atoi(token);
                    //printf("->>>>  %d\n",Faces[count - 144][X]);
                }else if(token_count == 3){
                    Faces[i][Z] = atoi(token);
                    for ( j=0; j < 3; j++ ) {
                        Box[i][0][j] = Vertices[ Faces[i][0] ][j];
                        Box[i][1][j] = Vertices[ Faces[i][0] ][j];
                  }

               for ( k=1; k < 3; k++ )
               for ( j=0; j < 3; j++ ) {
                  w = Vertices[ Faces[i][k] ][j];
                  //printf("->>>>  %d\n",Faces[i][k]);
                  if ( w < Box[i][0][j] ) Box[i][0][j] = w;
                  if ( w > Box[i][1][j] ) Box[i][1][j] = w;
               }
               /*
               printf("Bounding box: (%d,%d,%d);(%d,%d,%d)\n",
                  Box[i][0][0],
                  Box[i][0][1],
                  Box[i][0][2],
                  Box[i][1][0],
                  Box[i][1][1],
                  Box[i][1][2] );
                */
                }
                token_count++;
            }
            token = strtok(NULL," ");
            //free(token);
        }
    }
    if (line)
        free(line);
}
void read_com(void)
{
    FILE * fp;
    char * line = NULL;
    size_t len = 0;
    ssize_t read;
    int count = 0;
    //float a,b,c;
    fp = fopen("small.off", "r");
    int i ;
    if (fp == NULL)
        exit(EXIT_FAILURE);
    while ((read = getline(&line, &len, fp)) != -1) {
        count++;
        char *token = strtok(line, " ");
        int token_count = 0;
        while (token != NULL) {
            // init facets and vertices
            if(count <= 2){
                printf("setting of file  %s\n", token);
                if(token_count == 0){
                    com_vertices = atoi(token);
                }else if(token_count == 1){
                    com_facets = atoi(token);
                }
                token_count++;
            }else if(count > 3 && count <  n_vertices + 4){
               if(token_count == 0){
                    com_Vertices[count - 4][X] = atof(token);
                }else if(token_count == 1){
                    com_Vertices[count - 4][Y] = atof(token);
                }else{
                    com_Vertices[count - 4][Z] = atof(token);
                }
                token_count++;
            }else if(count >= n_vertices + 4){
                i = count - n_vertices - 4;
                if(token_count == 1){
                    com_Faces[i][X] = atoi(token);
                }else if(token_count == 2){
                    com_Faces[i][Y] = atoi(token);
                }else if(token_count == 3){
                    com_Faces[i][Z] = atoi(token);
                }
                token_count++;
            }
            token = strtok(NULL, " ");
        }
    }
    if (line)
        free(line);
}
