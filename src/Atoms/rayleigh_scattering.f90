MODULE rayleigh_scattering

 use atom_type, only       : AtomType
 use atmos_type, only      : atmos
 use spectrum_type, only   : NLTEspec
 use constant
 use math, only            : dpow, SQ

 IMPLICIT NONE

 double precision, parameter :: LONG_RAYLEIGH_WAVE=1.d6 !nm

 CONTAINS

 FUNCTION Rayleigh(icell, atom, scatt) result(res)
 ! ------------------------------------------------------------- !
  ! Rayleigh scattering by transitions from the ground state of
  ! neutral atoms.
  ! Sums scattering crosssections of all bound-bound
  ! transitions from the groundstate of the atom with lamda_red
  ! (the longest wavelength covered by the transition) less than wavelength 
  ! lambda.
  !
  ! See:
  ! -- Hubeny & Mihalas 2014 p. 155, eq. 6.44-6.45
  ! SigmaR \propto sigmaT * sum(f/(lambda/lambda0 - 1))**2
  !
  !
  ! Return scattering cross-section for all wavelengths
 ! ------------------------------------------------------------- !
  type (AtomType), intent(in)                               :: atom
  integer, intent(in)                                       :: icell
  logical                                                   :: res
  double precision, dimension(NLTEspec%Nwaves), intent(out) :: scatt
  integer                                                   :: kr, k
  double precision                                          :: lambda_red, lambda_limit, &
   															   sigma_e
  double precision, dimension(NLTEspec%Nwaves) 				:: fomega, lambda2
  
  lambda_limit = LONG_RAYLEIGH_WAVE
  sigma_e = 8.0*PI/3.0 * &
         dpow(Q_ELECTRON/(dsqrt(4.0*PI*EPSILON_0) *&
         (dsqrt(M_ELECTRON)*CLIGHT)), 4.d0)
  res = .false. !init, if .false. do not consider Rayleigh
                !of this atom in opac module.
                
  scatt = 0.

  if (atom%stage(1) /= 0) then
   write(*,*) "Lowest level of atom is not a neutral stage"
   write(*,*) "Not computing rayleigh for this atom"
   res = .false.
   RETURN
  end if
  
 !   find lambda_red, the longest wavelength covered by the
 !   transition less than lambda for this atom.
  if (atom%Nline > 0) then
   do kr=1,atom%Nline
    lambda_red = atom%lines(kr)%lambda(atom%lines(kr)%Nred) !reddest wavelength including
    														!velocity shifts.
    lambda_limit = min(lambda_limit, lambda_red)
   end do
  else
   res = .false.
   RETURN
  end if
  
  fomega = 0.0

  do kr=1,atom%Nline
   lambda_red = atom%lines(kr)%lambda(atom%lines(kr)%Nred)
   if (atom%lines(kr)%i.eq.1) then
    where((NLTEspec%lambda > lambda_limit).and.(NLTEspec%lambda > lambda_red))
     lambda2 = 1./((NLTEspec%lambda/atom%lines(kr)%lambda0)**2 -1.)
     fomega = fomega + (lambda2)**2 *atom%lines(kr)%fosc
    end where
   end if 
  end do
  scatt = sigma_e * fomega * atom%n(1,icell) !m^-1 = m^2 * m^-3
  
  if ((MAXVAL(scatt).gt.0)) then
    res = .true.
    RETURN
  end if

 RETURN
 END FUNCTION Rayleigh


END MODULE rayleigh_scattering