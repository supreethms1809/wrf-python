!======================================================================
!
! !IROUTINE: VIRTUAL -- Calculate virtual temperature (K)
!
! !DESCRIPTION:
!
!   This function returns a single value of virtual temperature in
!   K, given temperature in K and mixing ratio in kg/kg.  For an
!   array of virtual temperatures, use subroutine VIRTUAL_TEMP.
!
! !INPUT:
!    RATMIX - water vapor mixing ratio (kg/kg)
!    TEMP   - temperature (K)
!
! !OUTPUT:
!    TV     - Virtual temperature (K)
!

! NCLFORTSTART
REAL(KIND=8) FUNCTION TVIRTUAL(temp, ratmix)
    USE wrf_constants, ONLY : EPS

    !f2py threadsafe

    IMPLICIT NONE
    REAL(KIND=8), INTENT(IN) :: temp, ratmix

! NCLEND

    TVIRTUAL = temp*(EPS + ratmix)/(EPS*(1.D0 + ratmix))

    RETURN

END FUNCTION TVIRTUAL

! NCLFORTSTART
REAL(KIND=8) FUNCTION TONPSADIABAT(thte, prs, psadithte, psadiprs, psaditmk, gamma,&
                                   errstat, errmsg)
    USE wrf_constants, ONLY : ALGERR
!$OMP DECLARE SIMD (TONPSADIABAT) 
!!uniform(thte,prs,psadithte,psadiprs,psaditmk)
    !f2py threadsafe
    !f2py intent(in,out) :: cape, cin

    IMPLICIT NONE
    REAL(KIND=8), INTENT(IN) :: thte
    REAL(KIND=8), INTENT(IN) :: prs
    REAL(KIND=8), DIMENSION(150), INTENT(IN) :: psadithte
    REAL(KIND=8), DIMENSION(150), INTENT(IN) :: psadiprs
    REAL(KIND=8), DIMENSION(150,150), INTENT(IN) :: psaditmk
    REAL(KIND=8), INTENT(IN) :: gamma
    INTEGER, INTENT(INOUT) :: errstat
    CHARACTER(LEN=*), INTENT(INOUT) :: errmsg

! NCLEND

    REAL(KIND=8) :: fracjt
    REAL(KIND=8) :: fracjt2
    REAL(KIND=8) :: fracip
    REAL(KIND=8) :: fracip2
    
    INTEGER :: l1, h1, mid1, rang1, l2, h2, mid2, rang2
    INTEGER :: ip, ipch, jt, jtch

    !   This function gives the temperature (in K) on a moist adiabat
    !   (specified by thte in K) given pressure in hPa.  It uses a
    !   lookup table, with data that was generated by the Bolton (1980)
    !   formula for theta_e.

    !     First check if pressure is less than min pressure in lookup table.
    !     If it is, assume parcel is so dry that the given theta-e value can
    !     be interpretted as theta, and get temperature from the simple dry
    !     theta formula.

    IF (prs .LE. psadiprs(150)) THEN
        TONPSADIABAT = thte * (prs/1000.D0)**gamma
        RETURN
    END IF

    !   Otherwise, look for the given thte/prs point in the lookup table.

    jt = -1
    l1 = 1
    h1 = 149
    rang1 = h1 - l1
    mid1 = 0.5 * (h1 + l1)
    DO WHILE(rang1 .GT. 1)
        if(thte .GE. psadithte(mid1)) then
           l1 = mid1 
        else
           h1 = mid1 
        end if 
        rang1 = h1 - l1
        mid1 = 0.5 * (h1 + l1)
    END DO
    jt = l1

   ! DO jtch = 1, 150-1
   !     IF (thte .GE. psadithte(jtch) .AND. thte .LT. psadithte(jtch+1)) THEN
   !         jt = jtch
   !         EXIT
  !          !GO TO 213
  !      END IF
  !  END DO

        ip = -1
    l2 = 1
    h2 = 149
    rang2 = h2 - l2
    mid2 = 0.5 * (h2 + l2)
    DO WHILE(rang2 .GT. 1)
        if(prs .LE. psadiprs(mid2)) then
           l2 = mid2 
        else
           h2 = mid2 
        end if
        rang2 = h2 - l2
        mid2 = 0.5 * (h2 + l2)
    END DO
    ip = l2

   ! ip = -1
   ! DO ipch = 1, 150-1
   !     IF (prs .LE. psadiprs(ipch) .AND. prs .GT. psadiprs(ipch+1)) THEN
   !         ip = ipch
   !         EXIT
   !         !GO TO 215
   !     END IF
   ! END DO

    IF (jt .EQ. -1 .OR. ip .EQ. -1) THEN
        ! Set the error and return
        TONPSADIABAT = -1
        errstat = ALGERR
        WRITE(errmsg, *) "capecalc3d: Outside of lookup table bounds. prs,thte=", prs, thte
        RETURN
    END IF

    fracjt = (thte-psadithte(jt)) / (psadithte(jt+1)-psadithte(jt))
    fracjt2 = 1.D0 - fracjt
    fracip = (psadiprs(ip)-prs) / (psadiprs(ip)-psadiprs(ip+1))
    fracip2 = 1.D0 - fracip

    IF (psaditmk(ip,jt) .GT. 1D9 .OR. psaditmk(ip+1,jt) .GT. 1D9 .OR. &
        psaditmk(ip,jt+1) .GT. 1D9 .OR. psaditmk(ip+1,jt+1) .GT. 1D9) THEN
        ! Set the error and return
        TONPSADIABAT = -1
        errstat = ALGERR
        WRITE(errmsg, *) "capecalc3d: Tried to access missing temperature in lookup table. ", &
                 "Prs and Thte probably unreasonable. prs,thte=", prs, thte
        RETURN
    END IF

    TONPSADIABAT = fracip2*fracjt2*psaditmk(ip,jt) + fracip*fracjt2*psaditmk(ip+1,jt) + &
            fracip2*fracjt*psaditmk(ip,jt+1) + fracip*fracjt*psaditmk(ip+1,jt+1)

    RETURN

END FUNCTION TONPSADIABAT

!NCLFORTSTART
SUBROUTINE DLOOKUP_TABLE(psadithte, psadiprs, psaditmk, fname, errstat, errmsg)
    USE wrf_constants, ONLY : ALGERR

    !f2py threadsafe

    REAL(KIND=8), DIMENSION(150), INTENT(INOUT) :: psadithte, psadiprs
    REAL(KIND=8), DIMENSION(150,150), INTENT(INOUT) :: psaditmk
    CHARACTER(LEN=*), INTENT(IN) :: fname
    INTEGER, INTENT(INOUT) :: errstat
    CHARACTER(LEN=*), INTENT(INOUT) :: errmsg

!NCLEND

    ! Locals
    INTEGER :: iustnlist, i, nthte, nprs, ip, jt

    !      FNAME = 'psadilookup.dat'
    iustnlist = 33
    OPEN (UNIT=iustnlist, FILE=fname, FORM='formatted', STATUS='old')

    DO i = 1,14
        READ (iustnlist, FMT=*)
    END DO

    READ (iustnlist, FMT=*) nthte, nprs

    IF (nthte .NE. 150 .OR. nprs .NE. 150) THEN
        errstat = ALGERR
        errmsg = "Number of pressure or theta_e levels in lookup table file not 150"
        RETURN
    END IF

    READ (iustnlist, FMT="(5D15.7)") (psadithte(jt),jt=1,nthte)
    READ (iustnlist, FMT="(5D15.7)") (psadiprs(ip),ip=1,nprs)
    READ (iustnlist, FMT="(5D15.7)") ((psaditmk(ip,jt),ip=1,nprs),jt=1,nthte)

    CLOSE (iustnlist)

    RETURN

END SUBROUTINE DLOOKUP_TABLE


!     Historically, this routine calculated the pressure at full sigma
!     levels when RIP was specifically designed for MM4/MM5 output.
!     With the new generalized RIP (Feb '02), this routine is still
!     intended to calculate a set of pressure levels that bound the
!     layers represented by the vertical grid points, although no such
!     layer boundaries are assumed to be defined.  The routine simply
!     uses the midpoint between the pressures of the vertical grid
!     points as the bounding levels.  The array only contains mkzh
!     levels, so the pressure of the top of the uppermost layer is
!     actually excluded.  The kth value of pf is the lower bounding
!     pressure for the layer represented by kth data level.  At the
!     lower bounding level of the lowest model layer, it uses the
!     surface pressure, unless the data set is pressure-level data, in
!     which case it assumes the lower bounding pressure level is as far
!     below the lowest vertical level as the upper bounding pressure
!     level is above.
SUBROUTINE DPFCALC(prs, sfp, pf, miy, mjx, mkzh, ter_follow)

    REAL(KIND=8), DIMENSION(mkzh,miy,mjx), INTENT(IN) :: prs
    REAL(KIND=8), DIMENSION(miy,mjx), INTENT(IN) :: sfp
    REAL(KIND=8), DIMENSION(mkzh,miy,mjx), INTENT(OUT) :: pf
    INTEGER, INTENT(IN) :: ter_follow,miy,mjx,mkzh

    INTEGER :: i,j,k

    !  do j=1,mjx-1  Artifact of MM5
    DO j = 1,mjx
    !  do i=1,miy-1  staggered grid
      DO i = 1,miy
          DO k = 1,mkzh
              IF (k .EQ. mkzh) THEN
    !  terrain-following data
                  IF (ter_follow .EQ. 1) THEN
                      pf(k,i,j) = sfp(i,j)
    !  pressure-level data
                  ELSE
                      pf(k,i,j) = .5D0 * (3.D0*prs(k,i,j) - prs(k-1,i,j))
                  END IF
              ELSE
                  pf(k,i,j) = .5D0 * (prs(k+1,i,j) + prs(k,i,j))
              END IF
          END DO
      END DO
    END DO

    RETURN

END SUBROUTINE DPFCALC

!======================================================================
!
! !IROUTINE: capecalc3d -- Calculate CAPE and CIN
!
! !DESCRIPTION:
!
!   If i3dflag=1, this routine calculates CAPE and CIN (in m**2/s**2,
!   or J/kg) for every grid point in the entire 3D domain (treating
!   each grid point as a parcel).  If i3dflag=0, then it
!   calculates CAPE and CIN only for the parcel with max theta-e in
!   the column, (i.e. something akin to Colman's MCAPE).  By "parcel",
!   we mean a 500-m deep parcel, with actual temperature and moisture
!   averaged over that depth.
!
!   In the case of i3dflag=0,
!   CAPE and CIN are 2D fields that are placed in the k=mkzh slabs of
!   the cape and cin arrays.  Also, if i3dflag=0, LCL and LFC heights
!   are put in the k=mkzh-1 and k=mkzh-2 slabs of the cin array.
!


! Important!  The z-indexes must be arranged so that mkzh (max z-index) is the
! surface pressure.  So, pressure must be ordered in ascending order before
! calling this routine.  Other variables must be ordered the same (p,tk,q,z).

! Also, be advised that missing data values are not checked during the computation.
! Also also, Pressure must be hPa

! NCLFORTSTART
SUBROUTINE DCAPECALC3D(prs,tmk,qvp,ght,ter,sfp,cape,cin,&
            cmsg,miy,mjx,mkzh,i3dflag,ter_follow,&
            psafile, errstat, errmsg)
    USE wrf_constants, ONLY : ALGERR, CELKEL, G, EZERO, ESLCON1, ESLCON2, &
                          EPS, RD, CP, GAMMA, CPMD, RGASMD, GAMMAMD, TLCLC1, &
                          TLCLC2, TLCLC3, TLCLC4, THTECON1, THTECON2, THTECON3

    USE omp_lib
    IMPLICIT NONE

    !f2py threadsafe
    !f2py intent(in,out) :: cape, cin

    INTEGER, INTENT(IN) :: miy, mjx, mkzh, i3dflag, ter_follow
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(IN) :: prs
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(IN) :: tmk
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(IN) :: qvp
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(IN) :: ght
    REAL(KIND=8), DIMENSION(miy,mjx), INTENT(IN) :: ter
    REAL(KIND=8), DIMENSION(miy,mjx), INTENT(IN) ::sfp
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(OUT) :: cape
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(OUT) :: cin
    REAL(KIND=8), INTENT(IN) :: cmsg
    CHARACTER(LEN=*), INTENT(IN) :: psafile
    INTEGER, INTENT(INOUT) :: errstat
    CHARACTER(LEN=*), INTENT(INOUT) :: errmsg

! NCLFORTEND

    ! local variables
    INTEGER :: i, j, k, ilcl, kel, kk, klcl, klev, klfc, kmax, kpar, kpar1, kpar2
    REAL(KIND=8) :: davg, ethmax, q, t, p, e, eth, tlcl, zlcl
    REAL(KIND=8) :: pavg, tvirtual, p1, p2, pp1, pp2, th, totthe, totqvp, totprs
    REAL(KIND=8) :: cpm, deltap, ethpari, gammam, ghtpari, qvppari, prspari, tmkpari
    REAL(KIND=8) :: facden, fac1, fac2, qvplift, tmklift, tvenv, tvlift, ghtlift
    REAL(KIND=8) :: eslift, tmkenv, qvpenv, tonpsadiabat
    REAL(KIND=8) :: benamin, dz, pup, pdn
    REAL(KIND=8), DIMENSION(150) :: buoy, zrel, benaccum
    REAL(KIND=8), DIMENSION(mkzh,miy,mjx) :: prsf
    REAL(KIND=8), DIMENSION(150) :: psadithte, psadiprs
    REAL(KIND=8), DIMENSION(150,150) :: psaditmk
    LOGICAL :: elfound
    INTEGER :: tid, nthreads
    REAL :: t1,t2,t3,t4,rate
    REAL(KIND=8), DIMENSION(mkzh) :: eth_temp
    REAL(KIND=8) :: temp
    REAL(KIND=8), DIMENSION(mkzh,miy,mjx) :: prs_new
    REAL(KIND=8), DIMENSION(mkzh,miy,mjx) :: tmk_new
    REAL(KIND=8), DIMENSION(mkzh,miy,mjx) :: qvp_new
    REAL(KIND=8), DIMENSION(mkzh,miy,mjx) :: ght_new
    REAL(KIND=8), DIMENSION(mkzh,miy,mjx) :: cape_new
    REAL(KIND=8), DIMENSION(mkzh,miy,mjx) :: cin_new
    REAL(KIND=8), DIMENSION(mkzh) :: tmklift_new

    ! To remove compiler warnings
    tmkpari = 0
    qvppari = 0
    klev = 0
    klcl = 0
    kel = 0


    ! the comments were taken from a mark stoelinga email, 23 apr 2007,
    ! in response to a user getting the "outside of lookup table bounds"
    ! error message.

    ! tmkpari  - initial temperature of parcel, k
    !    values of 300 okay. (not sure how much from this you can stray.)

    ! prspari - initial pressure of parcel, hpa
    !    values of 980 okay. (not sure how much from this you can stray.)

    ! thtecon1, thtecon2, thtecon3
    !     these are all constants, the first in k and the other two have
    !     no units.  values of 3376, 2.54, and 0.81 were stated as being
    !     okay.

    ! tlcl - the temperature at the parcel's lifted condensation level, k
    !        should be a reasonable atmospheric temperature around 250-300 k
    !        (398 is "way too high")

    ! qvppari - the initial water vapor mixing ratio of the parcel,
    !           kg/kg (should range from 0.000 to 0.025)
    !

    !  calculated the pressure at full sigma levels (a set of pressure
    !  levels that bound the layers represented by the vertical grid points)
!CALL cpu_time(t1)
CALL cpu_time(t3)
!$OMP PARALLEL DO
DO i = 1,mjx
   DO j = 1,miy
      DO k = 1,mkzh 
         prs_new(k,j,i) = prs(j,i,k)
         tmk_new(k,j,i) = tmk(j,i,k)
         qvp_new(k,j,i) = qvp(j,i,k)
         ght_new(k,j,i) = ght(j,i,k)
      END DO
   END DO
END DO
!$OMP END PARALLEL DO
CALL cpu_time(t4)
print *,'Time for copy is ',(t4-t3)

CALL cpu_time(t1)    
    CALL DPFCALC(prs_new, sfp, prsf, miy, mjx, mkzh, ter_follow)

    !  before looping, set lookup table for getting temperature on
    !  a pseudoadiabat.

    CALL DLOOKUP_TABLE(psadithte, psadiprs, psaditmk, psafile, errstat, errmsg)

    IF (errstat .NE. 0) THEN
        RETURN
    END IF

!!$OMP PARALLEL DO PRIVATE(tlcl,gammam,cpm,ethpari, &
!!$OMP zlcl,ilcl,klcl,buoy,benamin,benaccum,zrel, &
!!$OMP qvplift,tmklift,ghtlift,tvlift,tvenv, &
!!$OMP qvpenv,tmkenv,eslift,elfound)
    DO j = 1,mjx
!call cpu_time(t3)
!!$OMP PARALLEL DO PRIVATE(tlcl,gammam,cpm,ethpari, &
!!$OMP zlcl,ilcl,klcl,buoy,benamin,benaccum,zrel, &
!!$OMP qvplift,tmklift,ghtlift,tvlift,tvenv, &
!!$OMP qvpenv,tmkenv,eslift,elfound)
      DO i = 1,miy
          cape(i,j,1) = 0.d0
          cin(i,j,1) = 0.d0
             
!$OMP SIMD          
           DO kpar = 2, mkzh

              ! Calculate temperature and moisture properties of parcel
              ! (note, qvppari and tmkpari already calculated above for 2d case.)
             
              tlcl = TLCLC1/(LOG(tmk_new(kpar,i,j)**TLCLC2/(MAX(1.D-20,qvp_new(kpar,i,j)*prs_new(kpar,i,j)/(EPS + qvp_new(kpar,i,j))))) - TLCLC3) + TLCLC4
             
              ethpari = tmk_new(kpar,i,j)*(1000.D0/prs_new(kpar,i,j))**(GAMMA*(1.D0 + GAMMAMD*qvp_new(kpar,i,j)))* &
                  EXP((THTECON1/tlcl - THTECON2)*qvp_new(kpar,i,j)*(1.D0 + THTECON3*qvp_new(kpar,i,j)))
                
              zlcl = ght_new(kpar,i,j) + (tmk_new(kpar,i,j) - tlcl)/(G/CP * (1.D0 + CPMD*qvp_new(kpar,i,j)))

           !   DO k = kpar,1,-1
           !       tmklift_new(k) = TONPSADIABAT(ethpari, prs_new(k,i,j), psadithte, psadiprs,&
           !                                  psaditmk, GAMMA, errstat, errmsg)
           !   END DO
              ! Calculate buoyancy and relative height of lifted parcel at
              ! all levels, and store in bottom up arrays.  add a level at the lcl,
              ! and at all points where buoyancy is zero.
              !
              ! For arrays that go bottom to top
              kk = 0
              ilcl = 0

              IF (ght_new(kpar,i,j) .GE. zlcl) THEN
                  ! Initial parcel already saturated or supersaturated.
                  ilcl = 2
                  klcl = 1
              END IF

             ! k = kpar
             ! DO WHILE (k .GE. 1)!k = kpar, 1, -1
!$OMP SIMD lastprivate(qvplift,tmklift,ghtlift,tvlift,tmkenv,qvpenv,tvenv,eslift,facden) 
            DO k = kpar,1,-1   
               ! For arrays that go bottom to top
                  kk = kk + 1

                  ! Model level is below lcl
                  IF (ght_new(k,i,j) .LT. zlcl) THEN
                      tmklift = tmk_new(kpar,i,j) - G/(CP * (1.D0 + CPMD*qvp_new(kpar,i,j))) * (ght_new(k,i,j) - ght_new(kpar,i,j))
                      tvenv = tmk_new(k,i,j)*(EPS + qvp_new(k,i,j))/(EPS*(1.D0 + qvp_new(k,i,j)))
                      tvlift = tmklift*(EPS + qvp_new(kpar,i,j))/(EPS*(1.D0 + qvp_new(kpar,i,j))) 
                      ghtlift = ght_new(k,i,j)
                  ELSE IF (ght(i,j,k) .GE. zlcl .AND. ilcl .EQ. 0) THEN
                      ! This model level and previous model level straddle the lcl,
                      ! so first create a new level in the bottom-up array, at the lcl.
                      facden = 1/(ght_new(k,i,j) - ght_new(k+1,i,j))
                      tmkenv = tmk_new(k+1,i,j)*((ght_new(k,i,j)-zlcl)*facden) + tmk_new(k,i,j)*((zlcl-ght_new(k+1,i,j))*facden)
                      qvpenv = qvp_new(k+1,i,j)*((ght_new(k,i,j)-zlcl)*facden) + qvp_new(k,i,j)*((zlcl-ght_new(k+1,i,j))*facden)
                      tvenv = tmkenv* (EPS + qvpenv) / (EPS * (1.D0 + qvpenv))
                      tvlift = tlcl* (EPS + qvp_new(kpar,i,j)) / (EPS *(1.D0 + qvp_new(kpar,i,j)))
                      ghtlift = zlcl
                      ilcl = 1
                  ELSE
                      tmklift = TONPSADIABAT(ethpari, prs_new(k,i,j), psadithte, psadiprs,&
                                             psaditmk, GAMMA, errstat, errmsg)
                      eslift = EZERO*EXP(ESLCON1*(tmklift - CELKEL)/(tmklift - ESLCON2))
                      qvplift = EPS*eslift/(prs_new(k,i,j) - eslift)
                      tvenv = tmk_new(k,i,j) * (EPS + qvp_new(k,i,j)) / (EPS * (1.D0 + qvp_new(k,i,j)))
                      tvlift = tmklift*(EPS + qvplift) / (EPS * (1.D0 + qvplift))
                      ghtlift = ght_new(k,i,j)
                  END IF
                  !  Buoyancy
                  buoy(kk) = G*(tvlift - tvenv)/tvenv
                  zrel(kk) = ghtlift - ght_new(kpar,i,j)
                  IF ((kk .GT. 1) .AND. (buoy(kk)*buoy(kk-1) .LT. 0.0D0)) THEN
                      ! Parcel ascent curve crosses sounding curve, so create a new level
                      ! in the bottom-up array at the crossing.
                      kk = kk + 1
                      buoy(kk) = buoy(kk-1)
                      zrel(kk) = zrel(kk-1)
                      buoy(kk-1) = 0.D0
                      zrel(kk-1) = zrel(kk-2) + buoy(kk-2)/&
                          (buoy(kk-2) - buoy(kk))*(zrel(kk) - zrel(kk-2))
                  END IF
                  IF (ilcl .EQ. 1) THEN
                      klcl = kk
                      ilcl = 2
                      CYCLE
                  END IF

              END DO
              
              kmax = kk
             ! IF (kmax .GT. 150) THEN
             !      print *,'kmax got too big'
             !     errstat = ALGERR
             !     WRITE(errmsg, *) 'capecalc3d: kmax got too big. kmax=',kmax
             !     RETURN
             ! END IF

              ! If no lcl was found, set klcl to kmax.  it is probably not really
              ! at kmax, but this will make the rest of the routine behave
              ! properly.
              IF (ilcl .EQ. 0) klcl=kmax

              ! Get the accumulated buoyant energy from the parcel's starting
              ! point, at all levels up to the top level.
              benaccum(1) = 0.0D0
              benamin = 9d9
              DO k = 2,kmax
                  dz = zrel(k) - zrel(k-1)
                  benaccum(k) = benaccum(k-1) + .5D0*dz*(buoy(k-1) + buoy(k))
                  IF (benaccum(k) .LT. benamin) THEN
                      benamin = benaccum(k)
                  END IF
              END DO
              ! Determine equilibrium level (el), which we define as the highest
              ! level of non-negative buoyancy above the lcl. note, this may be
              ! the top level if the parcel is still buoyant there.

              elfound = .FALSE.
              DO k = kmax,klcl,-1
                  IF (buoy(k) .GE. 0.D0) THEN
                      ! k of equilibrium level
                      kel = k
                      elfound = .TRUE.
                      EXIT
                  END IF
              END DO

              ! If we got through that loop, then there is no non-negative
              ! buoyancy above the lcl in the sounding.  in these situations,
              ! both cape and cin will be set to -0.1 j/kg. (see below about
              ! missing values in v6.1.0). also, where cape is
              ! non-zero, cape and cin will be set to a minimum of +0.1 j/kg, so
              ! that the zero contour in either the cin or cape fields will
              ! circumscribe regions of non-zero cape.

              ! In v6.1.0 of ncl, we added a _fillvalue attribute to the return
              ! value of this function. at that time we decided to change -0.1
              ! to a more appropriate missing value, which is passed into this
              ! routine as cmsg.

              IF (.NOT. elfound) THEN
                  !print *,'el not found'
                  cape(i,j,kpar) = cmsg
                  cin(i,j,kpar)  = cmsg
                  klfc = kmax
                  CYCLE
              END IF

              !   If there is an equilibrium level, then cape is positive.  we'll
              !   define the level of free convection (lfc) as the point below the
              !   el, but at or above the lcl, where accumulated buoyant energy is a
              !   minimum.  the net positive area (accumulated buoyant energy) from
              !   the lfc up to the el will be defined as the cape, and the net
              !   negative area (negative of accumulated buoyant energy) from the
              !   parcel starting point to the lfc will be defined as the convective
              !   inhibition (cin).

              !   First get the lfc according to the above definition.
              benamin = 9D9
              klfc = kmax
              DO k = klcl,kel
                  IF (benaccum(k) .LT. benamin) THEN
                      benamin = benaccum(k)
                      klfc = k
                  END IF
              END DO

              ! Now we can assign values to cape and cin

              cape(i,j,kpar) = MAX(benaccum(kel)-benamin, 0.1D0)
              cin(i,j,kpar) = MAX(-benamin, 0.1D0)

              ! cin is uninteresting when cape is small (< 100 j/kg), so set
              ! cin to -0.1 (see note about missing values in v6.1.0) in
              ! that case.

              ! In v6.1.0 of ncl, we added a _fillvalue attribute to the return
              ! value of this function. at that time we decided to change -0.1
              ! to a more appropriate missing value, which is passed into this
              ! routine as cmsg.

              IF (cape(i,j,kpar) .LT. 100.D0) cin(i,j,kpar) = cmsg

          END DO
      END DO
!!$OMP END PARALLEL DO
!call cpu_time(t4)
!print *,'Time for a single x ',(t4-t3)
    END DO
!!$OMP END PARALLEL DO
CALL cpu_time(t2)
print *,'Time taken in seconds ',(t2-t1)
    RETURN
END SUBROUTINE DCAPECALC3D

!======================================================================
!
! !IROUTINE: capecalc2d -- Calculate CAPE and CIN
!
! !DESCRIPTION:
!
!   If i3dflag=1, this routine calculates CAPE and CIN (in m**2/s**2,
!   or J/kg) for every grid point in the entire 3D domain (treating
!   each grid point as a parcel).  If i3dflag=0, then it
!   calculates CAPE and CIN only for the parcel with max theta-e in
!   the column, (i.e. something akin to Colman's MCAPE).  By "parcel",
!   we mean a 500-m deep parcel, with actual temperature and moisture
!   averaged over that depth.
!
!   In the case of i3dflag=0,
!   CAPE and CIN are 2D fields that are placed in the k=mkzh slabs of
!   the cape and cin arrays.  Also, if i3dflag=0, LCL and LFC heights
!   are put in the k=mkzh-1 and k=mkzh-2 slabs of the cin array.
!


! Important!  The z-indexes must be arranged so that mkzh (max z-index) is the
! surface pressure.  So, pressure must be ordered in ascending order before
! calling this routine.  Other variables must be ordered the same (p,tk,q,z).

! Also, be advised that missing data values are not checked during the
! computation.
! Also also, Pressure must be hPa

! NCLFORTSTART
SUBROUTINE DCAPECALC2D(prs,tmk,qvp,ght,ter,sfp,cape,cin,&
            cmsg,miy,mjx,mkzh,i3dflag,ter_follow,&
            psafile, errstat, errmsg)
    USE wrf_constants, ONLY : ALGERR, CELKEL, G, EZERO, ESLCON1, ESLCON2, &
                          EPS, RD, CP, GAMMA, CPMD, RGASMD, GAMMAMD, TLCLC1, &
                          TLCLC2, TLCLC3, TLCLC4, THTECON1, THTECON2, THTECON3

    USE omp_lib
    IMPLICIT NONE

    !f2py threadsafe
    !f2py intent(in,out) :: cape, cin

    INTEGER, INTENT(IN) :: miy, mjx, mkzh, i3dflag, ter_follow
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(IN) :: prs
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(IN) :: tmk
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(IN) :: qvp
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(IN) :: ght
    REAL(KIND=8), DIMENSION(miy,mjx), INTENT(IN) :: ter
    REAL(KIND=8), DIMENSION(miy,mjx), INTENT(IN) ::sfp
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(OUT) :: cape
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh), INTENT(OUT) :: cin
    REAL(KIND=8), INTENT(IN) :: cmsg
    CHARACTER(LEN=*), INTENT(IN) :: psafile
    INTEGER, INTENT(INOUT) :: errstat
    CHARACTER(LEN=*), INTENT(INOUT) :: errmsg

! NCLFORTEND


    ! local variables
    INTEGER :: i, j, k, ilcl, kel, kk, klcl, klev, klfc, kmax, kpar, kpar1, kpar2
    REAL(KIND=8) :: davg, ethmax, q, t, p, e, eth, tlcl, zlcl
    REAL(KIND=8) :: pavg, tvirtual, p1, p2, pp1, pp2, th, totthe, totqvp, totprs
    REAL(KIND=8) :: cpm, deltap, ethpari, gammam, ghtpari, qvppari, prspari, tmkpari
    REAL(KIND=8) :: facden, fac1, fac2, qvplift, tmklift, tvenv, tvlift, ghtlift
    REAL(KIND=8) :: eslift, tmkenv, qvpenv, tonpsadiabat
    REAL(KIND=8) :: benamin, dz, pup, pdn
    REAL(KIND=8), DIMENSION(150) :: buoy, zrel, benaccum
    REAL(KIND=8), DIMENSION(miy,mjx,mkzh) :: prsf
    REAL(KIND=8), DIMENSION(150) :: psadithte, psadiprs
    REAL(KIND=8), DIMENSION(150,150) :: psaditmk
    LOGICAL :: elfound
    INTEGER :: tid, nthreads
    REAL :: t1,t2,t3,t4,rate
    REAL(KIND=8), DIMENSION(mkzh) :: eth_temp

    ! To remove compiler warnings
    tmkpari = 0
    qvppari = 0
    klev = 0
    klcl = 0
    kel = 0


    ! the comments were taken from a mark stoelinga email, 23 apr 2007,
    ! in response to a user getting the "outside of lookup table bounds"
    ! error message.

    ! tmkpari  - initial temperature of parcel, k
    !    values of 300 okay. (not sure how much from this you can stray.)

    ! prspari - initial pressure of parcel, hpa
    !    values of 980 okay. (not sure how much from this you can stray.)

    ! thtecon1, thtecon2, thtecon3
    !     these are all constants, the first in k and the other two have
    !     no units.  values of 3376, 2.54, and 0.81 were stated as being
    !     okay.

    ! tlcl - the temperature at the parcel's lifted condensation level, k
    !        should be a reasonable atmospheric temperature around 250-300 k
    !        (398 is "way too high")

    ! qvppari - the initial water vapor mixing ratio of the parcel,
    !           kg/kg (should range from 0.000 to 0.025)
    !

    !  calculated the pressure at full sigma levels (a set of pressure
    !  levels that bound the layers represented by the vertical grid points)
    CALL DPFCALC(prs, sfp, prsf, miy, mjx, mkzh, ter_follow)

    !  before looping, set lookup table for getting temperature on
    !  a pseudoadiabat.

    CALL DLOOKUP_TABLE(psadithte, psadiprs, psaditmk, psafile, errstat, errmsg)

    IF (errstat .NE. 0) THEN
        RETURN
    END IF

CALL OMP_SET_NUM_THREADS(16)
    nthreads = omp_get_num_threads()

    DO j = 1,mjx
      DO i = 1,miy
          cape(i,j,1) = 0.d0
          cin(i,j,1) = 0.d0
              ! find parcel with max theta-e in lowest 3 km agl.
              ethmax = -1.d0
              DO k = 1,mkzh
                  IF (ght(i,j,k)-ter(i,j) .LT. 3000.d0) THEN
                      tlcl = TLCLC1 / (LOG(tmk(i,j,k)**((TLCLC2))/(MAX(qvp(i,j,k), 1.d-15)*prs(i,j,k)))/(EPS+MAX(qvp(i,j,k), 1.d-15))-TLCLC3)+TLCLC4
                      eth_temp(k) = tmk(i,j,k) * (1000.d0/prs(i,j,k))**(GAMMA*(1.d0 + GAMMAMD*(MAX(qvp(i,j,k), 1.d-15))))*&
                              EXP((THTECON1/tlcl - THTECON2)*(MAX(qvp(i,j,k), 1.d-15))*(1.d0 + THTECON3*(MAX(qvp(i,j,k), 1.d-15))))
                  END IF
              END DO
              DO k =1,mkzh
                  IF (eth_temp(k) .GT. ethmax) THEN
                     klev = k
                     ethmax = eth_temp(k)
                  END IF
              END DO

              kpar1 = klev
              kpar2 = klev


              ! Establish average properties of that parcel
              ! (over depth of approximately davg meters)

              davg = 500.d0
              pavg = davg*prs(i,j,kpar1)*&
                  G/(RD*tvirtual(tmk(i,j,kpar1), qvp(i,j,kpar1)))
              p2 = MIN(prs(i,j,kpar1)+.5d0*pavg, prsf(i,j,mkzh))
              p1 = p2 - pavg
              totthe = 0.D0
              totqvp = 0.D0
              totprs = 0.D0
              DO k = mkzh,2,-1
             ! DO k = 2,mkzh
                  IF (prsf(i,j,k) .LE. p1) EXIT !GOTO 35
                  IF (prsf(i,j,k-1) .GE. p2) CYCLE !GOTO 34
                  p = prs(i,j,k)
                  pup = prsf(i,j,k)
                  pdn = prsf(i,j,k-1)
                  q = MAX(qvp(i,j,k),1.D-15)
                  th = tmk(i,j,k)*(1000.D0/p)**(GAMMA*(1.D0 + GAMMAMD*q))
                  pp1 = MAX(p1,pdn)
                  pp2 = MIN(p2,pup)
                  IF (pp2 .GT. pp1) THEN
                      deltap = pp2 - pp1
                      totqvp = totqvp + q*deltap
                      totthe = totthe + th*deltap
                      totprs = totprs + deltap
                  END IF
              END DO
              qvppari = totqvp/totprs
              tmkpari = (totthe/totprs)*&
                  (prs(i,j,kpar1)/1000.D0)**(GAMMA*(1.D0+GAMMAMD*qvp(i,j,kpar1)))
       
!CALL CPU_TIME(t3)
          DO kpar = kpar1, kpar2

              ! Calculate temperature and moisture properties of parcel
              ! (note, qvppari and tmkpari already calculated above for 2d
              ! case.)

              prspari = prs(i,j,kpar)
              ghtpari = ght(i,j,kpar)
              gammam = GAMMA * (1.D0 + GAMMAMD*qvppari)
              cpm = CP * (1.D0 + CPMD*qvppari)

              e = MAX(1.D-20,qvppari*prspari/(EPS + qvppari))
              tlcl = TLCLC1/(LOG(tmkpari**TLCLC2/e) - TLCLC3) + TLCLC4
              ethpari = tmkpari*(1000.D0/prspari)**(GAMMA*(1.D0 + GAMMAMD*qvppari))*&
                  EXP((THTECON1/tlcl - THTECON2)*qvppari*(1.D0 + THTECON3*qvppari))
              zlcl = ghtpari + (tmkpari - tlcl)/(G/cpm)

              ! Calculate buoyancy and relative height of lifted parcel at
              ! all levels, and store in bottom up arrays.  add a level at the
              ! lcl,
              ! and at all points where buoyancy is zero.
              !
             !
              ! For arrays that go bottom to top
              kk = 0
              ilcl = 0

              IF (ghtpari .GE. zlcl) THEN
                  ! Initial parcel already saturated or supersaturated.
                  ilcl = 2
                  klcl = 1
              END IF

              k = kpar
              DO WHILE (k .GE. 1)!k = kpar, 1, -1
              !DO k = kpar, 1, -1
                  ! For arrays that go bottom to top
                  kk = kk + 1

                  ! Model level is below lcl
                  IF (ght(i,j,k) .LT. zlcl) THEN
                      qvplift = qvppari
                      tmklift = tmkpari - G/cpm*(ght(i,j,k) - ghtpari)
                      tvenv = tvirtual(tmk(i,j,k), qvp(i,j,k))
                      tvlift = tvirtual(tmklift, qvplift)
                      ghtlift = ght(i,j,k)
                  ELSE IF (ght(i,j,k) .GE. zlcl .AND. ilcl .EQ. 0) THEN
                      ! This model level and previous model level straddle the
                      ! lcl,
                      ! so first create a new level in the bottom-up array, at
                      ! the lcl.
                      tmklift = tlcl
                      qvplift = qvppari
                      facden = ght(i,j,k) - ght(i,j,k+1)
                      fac1 = (zlcl-ght(i,j,k+1))/facden
                      fac2 = (ght(i,j,k)-zlcl)/facden
                      tmkenv = tmk(i,j,k+1)*fac2 + tmk(i,j,k)*fac1
                      qvpenv = qvp(i,j,k+1)*fac2 + qvp(i,j,k)*fac1
                      tvenv = tvirtual(tmkenv, qvpenv)
                      tvlift = tvirtual(tmklift, qvplift)
                      ghtlift = zlcl
                      ilcl = 1
                  ELSE
                      tmklift = TONPSADIABAT(ethpari, prs(i,j,k), psadithte, psadiprs,&
                                             psaditmk, GAMMA, errstat, errmsg)
                      eslift = EZERO*EXP(ESLCON1*(tmklift - CELKEL)/(tmklift - ESLCON2))
                      qvplift = EPS*eslift/(prs(i,j,k) - eslift)
                      tvenv = tvirtual(tmk(i,j,k), qvp(i,j,k))
                      tvlift = tvirtual(tmklift, qvplift)
                      ghtlift = ght(i,j,k)
                  END IF
                  !  Buoyancy
                  buoy(kk) = G*(tvlift - tvenv)/tvenv
                  zrel(kk) = ghtlift - ghtpari
                  IF ((kk .GT. 1) .AND. (buoy(kk)*buoy(kk-1) .LT. 0.0D0)) THEN
                      ! Parcel ascent curve crosses sounding curve, so create a
                      ! new level
                      ! in the bottom-up array at the crossing.
                      kk = kk + 1
                      buoy(kk) = buoy(kk-1)
                      zrel(kk) = zrel(kk-1)
                      buoy(kk-1) = 0.D0
                      zrel(kk-1) = zrel(kk-2) + buoy(kk-2)/&
                          (buoy(kk-2) - buoy(kk))*(zrel(kk) - zrel(kk-2))
                 END IF
                  IF (ilcl .EQ. 1) THEN
                      klcl = kk
                      ilcl = 2
                      CYCLE
                  END IF

                  k = k - 1
              END DO

              kmax = kk
             ! IF (kmax .GT. 150) THEN
             !     errstat = ALGERR
             !     WRITE(errmsg, *) 'capecalc3d: kmax got too big. kmax=',kmax
             !     RETURN
             ! END IF

              ! If no lcl was found, set klcl to kmax.  it is probably not
              ! really
              ! at kmax, but this will make the rest of the routine behave
              ! properly.
              IF (ilcl .EQ. 0) klcl=kmax

              ! Get the accumulated buoyant energy from the parcel's starting
              ! point, at all levels up to the top level.
              benaccum(1) = 0.0D0
              benamin = 9d9
              DO k = 2,kmax
                  dz = zrel(k) - zrel(k-1)
                  benaccum(k) = benaccum(k-1) + .5D0*dz*(buoy(k-1) + buoy(k))
                  IF (benaccum(k) .LT. benamin) THEN
                      benamin = benaccum(k)
                  END IF
              END DO
              ! Determine equilibrium level (el), which we define as the highest
              ! level of non-negative buoyancy above the lcl. note, this may be
              ! the top level if the parcel is still buoyant there.

              elfound = .FALSE.
              DO k = kmax,klcl,-1
                  IF (buoy(k) .GE. 0.D0) THEN
                      ! k of equilibrium level
                      kel = k
                      elfound = .TRUE.
                      EXIT
                  END IF
              END DO

              ! If we got through that loop, then there is no non-negative
              ! buoyancy above the lcl in the sounding.  in these situations,
              ! both cape and cin will be set to -0.1 j/kg. (see below about
              ! missing values in v6.1.0). also, where cape is
              ! non-zero, cape and cin will be set to a minimum of +0.1 j/kg, so
              ! that the zero contour in either the cin or cape fields will
              ! circumscribe regions of non-zero cape.
             ! In v6.1.0 of ncl, we added a _fillvalue attribute to the return
              ! value of this function. at that time we decided to change -0.1
              ! to a more appropriate missing value, which is passed into this
              ! routine as cmsg.

              IF (.NOT. elfound) THEN
                  cape(i,j,kpar) = cmsg
                  cin(i,j,kpar)  = cmsg
                  klfc = kmax
                  CYCLE
              END IF


              !   If there is an equilibrium level, then cape is positive.
              !   we'll
              !   define the level of free convection (lfc) as the point below
              !   the
              !   el, but at or above the lcl, where accumulated buoyant energy
              !   is a
              !   minimum.  the net positive area (accumulated buoyant energy)
              !   from
              !   the lfc up to the el will be defined as the cape, and the net
              !   negative area (negative of accumulated buoyant energy) from
              !   the
              !   parcel starting point to the lfc will be defined as the
              !   convective
              !   inhibition (cin).

              !   First get the lfc according to the above definition.
              benamin = 9D9
              klfc = kmax
              DO k = klcl,kel
                  IF (benaccum(k) .LT. benamin) THEN
                      benamin = benaccum(k)
                      klfc = k
                  END IF
              END DO

              ! Now we can assign values to cape and cin

              cape(i,j,kpar) = MAX(benaccum(kel)-benamin, 0.1D0)
              cin(i,j,kpar) = MAX(-benamin, 0.1D0)

              ! cin is uninteresting when cape is small (< 100 j/kg), so set
              ! cin to -0.1 (see note about missing values in v6.1.0) in
              ! that case.

              ! In v6.1.0 of ncl, we added a _fillvalue attribute to the return
              ! value of this function. at that time we decided to change -0.1
              ! to a more appropriate missing value, which is passed into this
              ! routine as cmsg.

              IF (cape(i,j,kpar) .LT. 100.D0) cin(i,j,kpar) = cmsg

          END DO

              cape(i,j,mkzh) = cape(i,j,kpar1)
              cin(i,j,mkzh) = cin(i,j,kpar1)
    !  meters agl
              cin(i,j,mkzh-1) = zrel(klcl) + ghtpari - ter(i,j)
    !  meters agl
              cin(i,j,mkzh-2) = zrel(klfc) + ghtpari - ter(i,j)

      END DO
    END DO
    RETURN
END SUBROUTINE DCAPECALC2D
