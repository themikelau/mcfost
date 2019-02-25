! This module computes the metals bound-free opacitiy according
! to Kramer's law if Hydrogenic or using detailed photoionisation
! cross-section read in the atomic model.
!
! Note that Hydrogen bound-free is computed in the hydrogen.f90 module
!
! The module also computes the bound-bound opacity of metals (including
! Hydrogen this time) treated as PASSIVE atoms (either LTE populations or
! NLTE pops for a previous run) and sums all PASSIVE opacities in NLTEspec%chi and %eta
!
! chi in m^-1, eta in J/m3/s/Hz/sr
MODULE metal

 use atmos_type, only                : atmos, Hydrogen, Helium
 use constant
 use math, only                      : bezier3_interp
 use atom_type
 use spectrum_type, only			 : NLTEspec, initAtomOpac
 use hydrogen_opacities
 use voigtfunctions, only 			 : Voigt
 use broad, only 					 : Damping
 use thomson_scattering
 use Rayleigh_scattering
 use Planck

 ! MCFOST's original
 use mcfost_env, only : dp
 use molecular_emission, only		 : v_proj
 use parametres
 use input

 IMPLICIT NONE


 CONTAINS

 SUBROUTINE Metal_bf(id, icell)
 !cross-section in cm2 per particle is given by Kramers’ formula
  !with n the principal quantum number of the level i from
 !which the atom or ion is ionized, Z the ion charge, ν in Hz and gbf the dimensionless
 !Gaunt factor, a quantummechanical correction factor of order unity.
 !The Kramers cross-section decays ∼ ν−3 above the threshold (“edge”) frequency ν0,
 !being zero below it because the threshold energy is the required minimum. Think the
  ! inverse in terms of wavelengths
  integer, intent(in)							            :: icell, id
  logical 										            :: obtained_n
  integer                                                   :: m, kr, i, j, Z, nc
  type (AtomType)                                           :: metal
  type (AtomicContinuum)                                    :: continuum
  double precision                                          :: lambdaEdge, twohc, hc_k, &
       														   n_eff
  double precision, dimension(1) 							:: gbf_0, uu0
  double precision, dimension(NLTEspec%Nwaves)              :: twohnu3_c2, gijk, hc_kla,&
                                                               expla, alpha_la, uu, gbf
   obtained_n = .false. !true if the routine to read principal quantum number is fine

   twohc = (2. * HPLANCK * CLIGHT) / (NM_TO_M)**(3d0)
   hc_k = (HPLANCK * CLIGHT) / (KBOLTZMANN * NM_TO_M)
   
   if (atmos%Npassiveatoms==1 .and. atmos%PassiveAtoms(1)%ID == "H ") RETURN
   ! else if H is not passive (active) it will not be the first.
   ! If H is passive it is always the first one (And if active the first one).

   hc_kla = hc_k/NLTEspec%lambda !factor 1/NM_TO_M in hc_k
   twohnu3_c2 = twohc / NLTEspec%lambda**3
   expla = dexp(-hc_kla/atmos%T(icell))

  ! Go throught all bound-free transitions of each PASSIVE
  ! metal and add the opacity and emissivity if lambda
  ! is lower (greater) than the wavelength threshold lambdaEdge
  ! (the frequency threshold) and if greater (lower) than
  ! wavelength min (frequency max). See Hydrogen b-f for more
  ! informations, and Hubeny & Mihalas chap. 7


  do m=1,atmos%Npassiveatoms
  ! run over all passive atoms
   metal = atmos%PassiveAtoms(m)!atmos%Atoms(m)
   if (metal%ID == "H ") CYCLE !H cont is treated in Hydrogen_bf()

    do kr=1,metal%Ncont
     continuum = metal%continua(kr)
     i = continuum%i
     j = continuum%j !+1 wrt C indexing
     lambdaEdge = continuum%lambda0! or ionisation wavelength or wavelength
               ! associated to the minimal frquency needed
               ! to unbound an electron

    ! -> prevents dividing by zero
     ! even if lcompute_atomRT(icell) it is still possible to not have a continuum transition
     ! between the level i and j, but not for the others.
    if (metal%nstar(j,icell) <=0) then
       write(*,*) "(Metal_bf) Warning at icell=", icell," T(K)=", atmos%T(icell)
       write(*,*) metal%ID,"%n(j) density <= 0 for j=", j, metal%n(j,icell)
       write(*,*) "skipping this level"
       CYCLE
    end if

     Z = metal%stage(i) + 1
     !! Only for Hydrogen n_eff = dsqrt(metal%g(i)/2.)
     !obtained_n = getPrincipal(metal%label(continuum%i), n_eff)

     if (.not.obtained_n) &
        n_eff = Z*dsqrt(E_RYDBERG / (metal%E(continuum%j) - metal%E(continuum%i)))

     ! for this continuum of this line
     alpha_la = 0d0
     uu = n_eff*n_eff*HPLANCK*CLIGHT/(NM_TO_M*Z*Z * E_RYDBERG * NLTEspec%lambda)
     uu0 = n_eff*n_eff*HPLANCK*CLIGHT/(NM_TO_M*Z*Z * E_RYDBERG * lambdaEdge)
     if (.not.continuum%Hydrogenic) then

       CALL bezier3_interp(continuum%Nlambda,&
                           continuum%lambda, &
                           continuum%alpha,  & !Now the interpolation grid
             continuum%Nlambda, &
             NLTEspec%lambda(continuum%Nblue:continuum%Nred), &
             alpha_la(continuum%Nblue:continuum%Nred)) !end

     else
     
        gbf_0 = Gaunt_bf(1, uu0, n_eff)
         !continuum%alpha0 is the result of the photoionisation
         !cross-section at lambdaEdge=continuum%lambda0
         ! = HPLANCK*CLIGHT/(Ej - Ei)
         ! therefore we scale wrt the lambdaEdge
         ! alpha_la(lambda=lambdaEdge)=alpha0 (containing
         ! already the gaunt factor !! and factor 1/Z^2)
           
        gbf(continuum%Nblue:continuum%Nred) = Gaunt_bf(continuum%Nlambda, &
          uu(continuum%Nblue:continuum%Nred), n_eff)

        alpha_la(continuum%Nblue:continuum%Nred) = gbf(continuum%Nblue:continuum%Nred) * &
           continuum%alpha0*((NLTEspec%lambda(continuum%Nblue:continuum%Nred)/lambdaEdge)**3)*&
           n_eff/gbf_0(1)

     end if !continuum type
     
     gijk(continuum%Nblue:continuum%Nred) = metal%nstar(i,icell)/metal%nstar(j,icell) * &
       expla(continuum%Nblue:continuum%Nred)
     if (lstore_opac) then !we don't care about proc id id
      NLTEspec%AtomOpac%Kc(icell,continuum%Nblue:continuum%Nred,1) = &
                    NLTEspec%AtomOpac%Kc(icell,continuum%Nblue:continuum%Nred,1) + &
       				alpha_la(continuum%Nblue:continuum%Nred) * &
       				(1.-expla(continuum%Nblue:continuum%Nred))*metal%n(i,icell)

      NLTEspec%AtomOpac%jc(icell,continuum%Nblue:continuum%Nred) = &
     				NLTEspec%AtomOpac%jc(icell,continuum%Nblue:continuum%Nred) + &
       				twohnu3_c2(continuum%Nblue:continuum%Nred) * gijk(continuum%Nblue:continuum%Nred) * &
         			alpha_la(continuum%Nblue:continuum%Nred)*metal%n(j,icell)
     else !proc id is important
      NLTEspec%AtomOpac%chi_p(id,continuum%Nblue:continuum%Nred) = &
      				NLTEspec%AtomOpac%chi_p(id,continuum%Nblue:continuum%Nred) + &
       				alpha_la(continuum%Nblue:continuum%Nred) * &
       				(1.-expla(continuum%Nblue:continuum%Nred))*metal%n(i,icell)

      NLTEspec%AtomOpac%eta_p(id,continuum%Nblue:continuum%Nred) = &
      				NLTEspec%AtomOpac%eta_p(id,continuum%Nblue:continuum%Nred) + &
      				twohnu3_c2(continuum%Nblue:continuum%Nred) * gijk(continuum%Nblue:continuum%Nred) * &
         			alpha_la(continuum%Nblue:continuum%Nred)*metal%n(j,icell)     
     end if

    end do ! loop over Ncont
  end do !loop over metals

 RETURN
 END SUBROUTINE Metal_bf


 SUBROUTINE Metal_bb (id, icell,x,y,z,x1,y1,z1,u,v,w,l)
  ! Computes the emissivity and extinction of passive lines.
  ! i.e., Atoms with detailed atomic structures read but
  ! not treated in NLTE.
  ! Because damping is wavelength dependent and depend only on
  ! the grid (cell) points, here, if line%damping_initialized
  ! do not CALL Damping()
  ! the x,y,z and u,v,w quantities are used to compute the projected velocities at the
  ! cell point we are computing the opacities.
  ! Chip is only computed in Stokes transfer and contains the magneto-optical elements.
  integer 													:: kr, m, i, j, NrecStokes
  integer, intent(in) 							            :: icell, id
  double precision, intent(in) 					            :: x,y,z,u,v,w,& !positions and angles used to project
                                				               x1,y1,z1, &      ! velocity field and magnetic field
                                				               l !physical length of the cell
  character(len=20)							                :: VoigtMethod = "HUMLICEK"
  double precision, dimension(NLTEspec%Nwaves)              :: phi, vvoigt, phiPol, phip, &
 															   Vij, vv
  double precision 											:: twohnu3_c2, hc, fourPI, &
      														   hc_4PI, gij
  integer, parameter										:: NvspaceMax = 101
  double precision, dimension(NvspaceMax)					:: omegav
  integer													:: Nvspace, nv
  double precision 											:: delta_vol_phi, xphi, yphi, zphi,&
  															   v0, v1, dv
  type (AtomicLine)										    :: line
  type (AtomType)											:: atom

  hc = HPLANCK * CLIGHT
  fourPI = 4.*PI
  hc_4PI = hc/fourPI
write(*,*) "in metal_bb"
  ! v_proj in m/s at point icell
  omegav = 0d0
  Nvspace = 1
  if (.not.lstatic) then
   if (lmagnetoaccr.or.linfall.or.lkeplerian) then
    v0 = v_proj(icell,x,y,z,u,v,w)
   else !not infinite resol, replaced by lVoronoi case in a near futur =)
    v0 = atmos%Vxyz(icell,1)*u + atmos%Vxyz(icell,2)*v + atmos%Vxyz(icell,3)*w
   end if
   omegav(1) = v0
   !the following line is not mandatory, anyway.. Nvspace=1 at the init phase
   if (lVoronoi) omegav(Nvspace) = v0 !velocity constant in the cell
  end if

  if (atmos%magnetized) then
   !! Magneto-optical elements (f, and r, LL04)
  end if

  do m=1,atmos%Npassiveatoms
   atom = atmos%PassiveAtoms(m)
   
    !velocity projected along a path between one border of the cell to the other
    if (.not.lstatic .and. .not.lVoronoi .and.&
    	(lmagnetoaccr.or.linfall.or.lkeplerian)) then ! velocity is varying across the cell
     v1 = v_proj(icell,x1,y1,z1,u,v,w)
     dv = dabs(v1-v0) 
     !write(*,*) v0/1000, v1/1000, dv/1000
     Nvspace = max(2,nint(20*dv/atom%vbroad(icell)))
     Nvspace = min(Nvspace,NvspaceMax) !Ensure that we never have an allocation error
     omegav(Nvspace) = v1
     !write(*,*) Nvspace, Nvspacemax
     do nv=2,Nvspace-1
      delta_vol_phi = (real(nv,kind=dp))/(real(Nvspace,kind=dp)) * l
      xphi=x+delta_vol_phi*u
      yphi=y+delta_vol_phi*v
      zphi=z+delta_vol_phi*w
      omegav(nv) = v_proj(icell,xphi,yphi,zphi,u,v,w)
      !write(*,*) icell, omegav(nv)/1d3
     end do 
    end if

    do kr=1,atom%Nline ! for this atom go over all transitions
                       ! bound-bound
     line = atom%lines(kr)
     i = line%i
     j = line%j

!     if ((atom%n(j,icell) <=0).or.(atom%n(i,icell) <=0)) CYCLE !"no contrib to opac"
     ! -> prevents dividing by zero
     ! even if lcompute_atomRT(icell) it is still possible to not have a transition
     ! between the levels i and j, but not for the others.
   if ((atom%n(j,icell) <=0).or.(atom%n(i,icell) <=0)) then !no transition
       write(*,*) "(Metal_bb) Warning at icell=", icell," T(K)=", atmos%T(icell)
       write(*,*) atom%ID," density <= 0 ", i, j, line%lambda0, atom%n(i,icell), atom%n(j,icell)
       write(*,*) "skipping this level"
      CYCLE
    end if

     phi = 0d0
     phip = 0d0
     phiPol = 0d0
     ! line dependent only
     vv(line%Nblue:line%Nred) = (NLTEspec%lambda(line%Nblue:line%Nred)-line%lambda0) * &
           CLIGHT / (line%lambda0 * atom%vbroad(icell))

     gij = line%Bji / line%Bij
     twohnu3_c2 = line%Aji / line%Bji
     
     if (line%voigt) then
      !some work to do here if line%damping_initialized = .true.==kept on the whole grid.
      CALL Damping(icell, atom, kr, line%adamp)
       ! init for this line of this atom accounting for Velocity fields
       do nv=1, Nvspace !one iteration if 1) No velocity fields or lstatic
                        !                 2) Voronoi grid is used
        vvoigt(line%Nblue:line%Nred) = vv(line%Nblue:line%Nred) - &
                                       omegav(nv) / atom%vbroad(icell)

        phi(line%Nblue:line%Nred) = phi(line%Nblue:line%Nred) + &
            Voigt(line%Nlambda, line%adamp,vvoigt(line%Nblue:line%Nred), &
                  phip, VoigtMethod) / Nvspace !1 if no vel or Voronoi
!       phiPol(line%Nblue:line%Nred) = phiPol(line%Nblue:line%Nred) + &
!              phip(line%Nblue:line%Nred) + Nvspace
      end do
     else !Gaussian
      do nv=1, Nvspace
        vvoigt(line%Nblue:line%Nred) = vv(line%Nblue:line%Nred) - omegav(nv) / atom%vbroad(icell)
       phi(line%Nblue:line%Nred) = phi(line%Nblue:line%Nred) + &
         dexp(-(vvoigt(line%Nblue:line%Nred))**2) / Nvspace
       ! phip = dphi/dv or more accurate with Fvoigt for a=0
       !phiPol = phiPol + dphi/dv etc
      end do
     end if !line%voigt

     !Sum up all contributions for this line with the other
!      Vij(iLam) = hc_4PI * line%Bij * phi(iLam) / (SQRTPI * atom%vbroad(icell))
     Vij(line%Nblue:line%Nred) = &
      hc_4PI * line%Bij * phi(line%Nblue:line%Nred) / (SQRTPI * atom%vbroad(icell))
!      chi(iLam) = chi(iLam) + Vij(iLam) * (atom%n(i,icell)-gij*atom%n(j,icell))
     NLTEspec%AtomOpac%chi_p(id,line%Nblue:line%Nred) = &
     		NLTEspec%AtomOpac%chi_p(id,line%Nblue:line%Nred) + &
       		Vij(line%Nblue:line%Nred) * (atom%n(i,icell)-gij*atom%n(j,icell))
!      eta(iLam) = eta(iLam) + twohnu3_c2 * gij * Vij(iLam) * atom%n(j,icell)
     NLTEspec%AtomOpac%eta_p(id,line%Nblue:line%Nred) = &
     		NLTEspec%AtomOpac%eta_p(id,line%Nblue:line%Nred) + &
       		twohnu3_c2 * gij * Vij(line%Nblue:line%Nred) * atom%n(j,icell)

       
     !dealloc indexes for next line
!     deallocate(iLam)
    end do !end loop on lines for this atom
  end do !end loop over Natom

 RETURN
 END SUBROUTINE Metal_bb

 SUBROUTINE Metal_bb_lambda (id, la, icell,x,y,z,x1,y1,z1,u,v,w,l)
  integer 													:: kr, m, i, j, NrecStokes
  integer, intent(in) 							            :: icell, la, id
  double precision, intent(in) 					            :: x,y,z,u,v,w,& 
                                				               x1,y1,z1,l
  character(len=20)							                :: VoigtMethod = "HUMLICEK"
  double precision, dimension(1)                            :: phi, vvoigt, phiPol, phip, &
 															   Vij, vv
  double precision 											:: twohnu3_c2, hc, fourPI, &
      														   hc_4PI, gij
  integer, parameter										:: NvspaceMax = 101
  double precision, dimension(NvspaceMax)					:: omegav
  integer													:: Nvspace, nv
  double precision 											:: delta_vol_phi, xphi, yphi, zphi,&
  															   v0, v1, dv
  type (AtomicLine)										    :: line
  type (AtomType)											:: atom

  hc = HPLANCK * CLIGHT
  fourPI = 4.*PI
  hc_4PI = hc/fourPI

  !check that NLTEspec%AtomOpac%eta_p(id,:) = 0d0 here

  ! v_proj in m/s at point icell
  omegav = 0d0
  Nvspace = 1
  if (.not.lstatic) then
   !if (lmagnetoaccr) then
   if (lmagnetoaccr.or.linfall.or.lkeplerian) then
    v0 = v_proj(icell,x,y,z,u,v,w)
   else !not infinite resol
    v0 = atmos%Vxyz(icell,1)*u + atmos%Vxyz(icell,2)*v + atmos%Vxyz(icell,3)*w
   end if
   omegav(1) = v0
   !the following line is not mandatory, anyway.. Nvspace=1 at the init phase
   if (lVoronoi) omegav(Nvspace) = v0 !velocity constant in the cell
  end if

  if (atmos%magnetized) then
   !! Magneto-optical elements (f, and r, LL04)
  end if

  !do m=1,atmos%Natom ! go over all atoms
  do m=1,atmos%Npassiveatoms
   atom = atmos%PassiveAtoms(m)!atmos%Atoms(m)
   !if (atom%active) CYCLE ! go to next passive atom
   
    !velocity projected along a path between one border of the cell to the other
    !if (.not.lstatic .and. .not.atmos%Voronoi .and.lmagnetoaccr) then ! velocity is varying across the cell
    if (.not.lstatic .and. .not.lVoronoi .and.&
    	(lmagnetoaccr.or.linfall.or.lkeplerian)) then
     v1 = v_proj(icell,x1,y1,z1,u,v,w)
     dv = dabs(v1-v0) 
     Nvspace = max(2,nint(20*dv/atom%vbroad(icell)))
     Nvspace = min(Nvspace,NvspaceMax) !Ensure that we never have an allocation error
     omegav(Nvspace) = v1
     do nv=2,Nvspace-1
      delta_vol_phi = (real(nv,kind=dp))/(real(Nvspace,kind=dp)) * l
      xphi=x+delta_vol_phi*u
      yphi=y+delta_vol_phi*v
      zphi=z+delta_vol_phi*w
      omegav(nv) = v_proj(icell,xphi,yphi,zphi,u,v,w)
     end do 
    end if

    do kr=1,atom%Nline ! for this atom go over all transitions
                       ! bound-bound
     line = atom%lines(kr)
     i = line%i
     j = line%j
     
     !wavelength does not fall inside line domaine? OK cylcle
     if ((NLTEspec%lambda(la) < NLTEspec%lambda(line%Nblue)).or.&
        (NLTEspec%lambda(la) > NLTEspec%lambda(line%Nred))) then
!        write(*,*) NLTEspec%lambda(la), " beyond line edge:", j, i
!        write(*,*) NLTEspec%lambda(line%Nblue), NLTEspec%lambda(line%Nred)
!        write(*,*) "Skipping"
       CYCLE
     end if

!     if ((atom%n(j,icell) <=0).or.(atom%n(i,icell) <=0)) CYCLE !"no contrib to opac"
   if ((atom%n(j,icell) <=0).or.(atom%n(i,icell) <=0)) then !no transition
       write(*,*) "(Metal_bb_lambda) Warning at icell=", icell," T(K)=", atmos%T(icell)
       write(*,*) atom%ID," density <= 0 ", i, j, line%lambda0, atom%n(i,icell), atom%n(j,icell)
       write(*,*) "skipping this level"
      CYCLE
    end if

     phi = 0d0
     phip = 0d0
     phiPol = 0d0
     ! line dependent only
     vv(1) = (NLTEspec%lambda(la)-line%lambda0) * &
           CLIGHT / (line%lambda0 * atom%vbroad(icell))

     gij = line%Bji / line%Bij
     twohnu3_c2 = line%Aji / line%Bji
     
     if (line%voigt) then
      !some work to do here if line%damping_initialized = .true.==kept on the whole grid.
      CALL Damping(icell, atom, kr, line%adamp)
       ! init for this line of this atom accounting for Velocity fields
       do nv=1, Nvspace 
        vvoigt(1) = vv(1) -  omegav(nv) / atom%vbroad(icell)

        phi = phi + Voigt(1, line%adamp,vvoigt,phip, VoigtMethod) / Nvspace 
      end do
     else !Gaussian
      do nv=1, Nvspace
        vvoigt(1) = vv(1) - omegav(nv) / atom%vbroad(icell)
       phi(1) = phi(1) + dexp(-(vvoigt(1))**2) / Nvspace
      end do
     end if !line%voigt
    
     
     Vij(1) = hc_4PI * line%Bij * phi(1) / (SQRTPI * atom%vbroad(icell))
     NLTEspec%AtomOpac%chi_p(id,la) = NLTEspec%AtomOpac%chi_p(id,la) +&
     								  Vij(1) * (atom%n(i,icell)-gij*atom%n(j,icell))
     NLTEspec%AtomOpac%eta_p(id,la) = NLTEspec%AtomOpac%eta_p(id,la) +&
     								  twohnu3_c2 * gij * Vij(1) * atom%n(j,icell)

    end do !end loop on lines for this atom
  end do !end loop over Natom

 RETURN
 END SUBROUTINE Metal_bb_lambda
 
 SUBROUTINE BackgroundContinua (icell)
  integer, intent(in) :: icell
  double precision, dimension(NLTEspec%Nwaves) :: chi, eta, Bpnu!,sca

  if (.not.atmos%lcompute_atomRT(icell)) RETURN
  
   CALL Bplanck(atmos%T(icell), Bpnu)

   chi = 0d0
   eta = 0d0

   NLTEspec%AtomOpac%Kc(icell,:,1) = Thomson(icell)

   CALL Rayleigh(1, icell, Hydrogen)
   if (associated(Helium)) CALL Rayleigh(1, icell, Helium)

   NLTEspec%AtomOpac%Kc(icell,:,2) = NLTEspec%AtomOpac%Kc(icell,:,1)

   CALL Hydrogen_ff(icell, chi)
   NLTEspec%AtomOpac%Kc(icell,:,1) = NLTEspec%AtomOpac%Kc(icell,:,1) + chi
   NLTEspec%AtomOpac%jc(icell,:) = NLTEspec%AtomOpac%jc(icell,:) + chi * Bpnu
   
   CALL Hminus_bf(icell, chi,eta)
   NLTEspec%AtomOpac%Kc(icell,:,1) = NLTEspec%AtomOpac%Kc(icell,:,1) + chi
   NLTEspec%AtomOpac%jc(icell,:) = NLTEspec%AtomOpac%jc(icell,:) + eta
   
   CALL Hminus_ff(icell, chi)
   NLTEspec%AtomOpac%Kc(icell,:,1) = NLTEspec%AtomOpac%Kc(icell,:,1) + chi
   NLTEspec%AtomOpac%jc(icell,:) = NLTEspec%AtomOpac%jc(icell,:) + chi * Bpnu

   if (.not.Hydrogen%active) then !passive bound-free
    CALL Hydrogen_bf(icell, chi, eta)
    NLTEspec%AtomOpac%Kc(icell,:,1) = NLTEspec%AtomOpac%Kc(icell,:,1) + chi
    NLTEspec%AtomOpac%jc(icell,:) = NLTEspec%AtomOpac%jc(icell,:) + eta
   end if

   if (atmos%Npassiveatoms == 0) RETURN !no passive bound-bound and bound-free
   CALL Metal_bf(1, icell) !here we do not need id, because lstore_atom_opac=.true.


 RETURN
 END SUBROUTINE BackgroundContinua
 
 SUBROUTINE BackgroundLines(id,icell,x,y,z,x1,y1,z1,u,v,w,l)
  integer, intent(in) :: icell, id
  double precision, intent(in) :: x, y, z, u, v, w, &
                                  x1, y1, z1, l

  if (.not.atmos%lcompute_atomRT(icell)) RETURN 

   if (atmos%Npassiveatoms == 0) RETURN
   CALL Metal_bb(id, icell, x, y, z, x1, y1, z1, u, v, w, l)

 RETURN
 END SUBROUTINE BackgroundLines
 
 SUBROUTINE BackgroundLines_lambda(la,id,icell,x,y,z,x1,y1,z1,u,v,w,l)
  integer, intent(in) :: icell, id, la
  double precision, intent(in) :: x, y, z, u, v, w, &
                                  x1, y1, z1, l

  if (.not.atmos%lcompute_atomRT(icell)) RETURN 


   if (atmos%Npassiveatoms == 0) RETURN
   CALL Metal_bb_lambda(id, la, icell, x, y, z, x1, y1, z1, u, v, w, l)

 RETURN
 END SUBROUTINE BackgroundLines_lambda

 SUBROUTINE Background(id,icell,x,y,z,x1,y1,z1,u,v,w,l)
  integer, intent(in) :: icell, id
  double precision, intent(in) :: x, y, z, u, v, w, &
                                  x1, y1, z1, l!only relevant for b-b when vector fields are present
  double precision, dimension(NLTEspec%Nwaves) :: chi, eta, Bpnu, chip!, sca

  if (.not.atmos%lcompute_atomRT(icell)) RETURN !nH <= tiny_nH or T <= tiny_T == empty cell
  ! all opac are zero, return.

!   if ((atmos%nHtot(icell)==0d0).or.(atmos%T(icell)==0d0)) &
!     RETURN ! stoping for this cell,
            ! it is free of (significant) gas
            ! so no emission/absorption. Coefficients set to 0d0 for all wavelengths
  !Do not forget that it is still possible however, that lcompute_atomRT is TRUE,
  !but that the temperature is too low to have all the levels non zero.
  !The compute_atomRT ensures that at least one level has non-zero populations,
  !to avoid division by zero.

   CALL Bplanck(atmos%T(icell), Bpnu)

   chi = 0d0
   eta = 0d0
!   sca = 0d0
   chip = 0d0


!    if (Rayleigh(icell, Hydrogen, sca)) NLTEspec%AtomOpac%sca_c(id,:) = sca
!    NLTEspec%AtomOpac%sca_c(id,:) =  NLTEspec%AtomOpac%sca_c(id,:) + Thomson(icell)
!    if (associated(Helium)) then
!     if (Rayleigh(icell, Helium, sca)) NLTEspec%AtomOpac%sca_c(id,:) = &
!           NLTEspec%AtomOpac%sca_c(id,:) + sca
!    end if
   !CALL HRayleigh(icell,Hydrogen, sca)
   !NLTEspec%AtomOpac%sca_c(id,:) = NLTEspec%AtomOpac%sca_c(id,:) + sca
   NLTEspec%AtomOpac%sca_c(id,:) = Thomson(icell) !init then update
   CALL Rayleigh(id, icell, Hydrogen)
   if (associated(Helium)) CALL Rayleigh(id, icell, Helium)


   NLTEspec%AtomOpac%chi_p(id,:) = NLTEspec%AtomOpac%sca_c(id,:)

   CALL Hydrogen_ff(icell, chi)
   NLTEspec%AtomOpac%chi_p(id,:) = NLTEspec%AtomOpac%chi_p(id,:) + chi
   NLTEspec%AtomOpac%eta_p(id,:) = NLTEspec%AtomOpac%eta_p(id,:) + chi * Bpnu

   CALL Hminus_bf(icell, chi, eta)
   NLTEspec%AtomOpac%chi_p(id,:) = NLTEspec%AtomOpac%chi_p(id,:) + chi
   NLTEspec%AtomOpac%eta_p(id,:) = NLTEspec%AtomOpac%eta_p(id,:) + eta

   CALL Hminus_ff(icell, chi)
   NLTEspec%AtomOpac%chi_p(id,:) = NLTEspec%AtomOpac%chi_p(id,:) + chi
   NLTEspec%AtomOpac%eta_p(id,:) = NLTEspec%AtomOpac%eta_p(id,:) + chi * Bpnu

   if (.not.Hydrogen%active) then !passive bound-free !do not enter if active !!!
    CALL Hydrogen_bf(icell, chi, eta)
    NLTEspec%AtomOpac%chi_p(id,:) = NLTEspec%AtomOpac%chi_p(id,:) + chi
    NLTEspec%AtomOpac%eta_p(id,:) = NLTEspec%AtomOpac%eta_p(id,:) + eta
   end if
   
   if (atmos%Npassiveatoms == 0) RETURN !no passive bound-bound and bound-free
   ! we avoid H passive in metal_bf if H is passive
   						!, chi, eta)
    CALL Metal_bf(id, icell) !Return if Npassive=1 and PassiveAtoms(1)==" H"
!     NLTEspec%AtomOpac%chi_p(id,:) = NLTEspec%AtomOpac%chi_p(id,:) + chi
!     NLTEspec%AtomOpac%eta_p(id,:) = NLTEspec%AtomOpac%eta_p(id,:) + eta

   !keep pure continuum opacities now
   if (MINVAL(NLTEspec%AtomOpac%eta_p(id,:))<0 .or. &
    MINVAL(NLTEspec%AtomOpac%chi_p(id,:)) < 0) then
    write(*,*) "err, negative opac"
    stop
   end if
   NLTEspec%AtomOpac%eta_c(id,:) = NLTEspec%AtomOpac%eta_p(id,:)
   NLTEspec%AtomOpac%chi_c(id,:) = NLTEspec%AtomOpac%chi_p(id,:)

   ! we already RETURNs if no passive transitions (H included)
   CALL Metal_bb(id, icell, x, y, z, x1, y1, z1, u, v, w, l)

 RETURN
 END SUBROUTINE Background

END MODULE metal
