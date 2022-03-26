! Hydrogen, bound-free, free-free and continuum opacities
! - H b-f and f-f --> H b-f is now computed in metal.f90 with the other atoms
! - H^- b-f and f-f
!  free-free emissivity is obtained by
! -> eta_ff = chi_ff * Bplanck
!
!
! Opacities in m^-1 (chi)
! Emissivities in J/s/m3/Hz/sr (eta)
module background_opacity

  !all background opacities that are avaluated on some lambda grid.
  ! for atom type transitions, Nblue, Nred are needed so it depends on either lambda or lambda_cont !

  use atom_type, only : AtomicContinuum, find_continuum, AtomType
  use atmos_type, only : Hydrogen, Helium, T, ne, Elements, nHmin, nHtot, PassiveAtoms, Npassiveatoms
  use constant
  use math, only : locate, linear_1D_sorted, interp1d_sorted, interp1D, interp2D
  use occupation_probability, only : D_i, wocc_n
  use parametres, only : ldissolve

  use constantes, only : tiny_dp
  use mcfost_env, only : dp
  use utils, only 	  : interp

  implicit none
	
	real, parameter :: lambda_limit_HI_rayleigh = 91.1763062831680!102.6 !nm
	real, parameter :: lambda_limit_HeI_rayleigh = 140.0 !nm
!   real(kind=dp), parameter :: LONG_RAYLEIGH_WAVE=1.d6 !nm
  !!integer, parameter :: NJOHN=6, NFF=17, NTHETA=16

contains

  function Thomson(icell)
    ! ------------------------------------------------------------- !
    ! Thomson scattering cross-section in non relativistic limit.
    ! (i.e., wavelength independent) x ne density.
    ! unit m^-1
    ! ------------------------------------------------------------- !
    integer, intent(in) 			:: icell
    real(kind=dp)				    :: Thomson

    Thomson = ne(icell) * sigma_e

    return
  end function Thomson
  
  !The splitting of Rayleigh scattering in a depth dependent term (like Thomson(icell))
  ! and wavelength term makes both the storage and the evaluation more efficient.
  !And, easier to include in J calculation!
  function HI_rayleigh_part1(icell)
    ! ------------------------------------------------------------- !
    ! H I Rayleigh scattering cross-section x nHI.
    ! unit m^-1
    ! ------------------------------------------------------------- ! 	
    integer, intent(in) :: icell
  	real(kind=dp) :: HI_rayleigh_part1
  	
!   	HI_rayleigh_part1 = sigma_e * sum(Hydrogen%n(1:Hydrogen%Nlevel-1,icell)) !m^-1
  	HI_rayleigh_part1 = sigma_e * Hydrogen%n(1,icell)

	return  
  end function HI_rayleigh_part1
  
  subroutine init_HI_rayleigh_part2(N, Lambda,HI_rayleigh_part2, lim)
    ! ------------------------------------------------------------- !
    ! H I Rayleigh scattering cross-section.
    ! wavelength dependent term
    ! ------------------------------------------------------------- ! 
    integer, intent(in) :: N
    real(kind=dp), intent(in) :: Lambda(N)
    real(kind=dp), intent(out) :: HI_rayleigh_part2(N)
    real(kind=dp), intent(in), optional :: lim
    real :: lambda_limit_lya
    
    !using the reddest wavelength covered by Lyman alpha ? 
    if (present(lim)) then
    	lambda_limit_lya = lim
    	write(*,*) " Limit for H Rayleigh scattering sets to ", lim
    else
    	lambda_limit_lya = lambda_limit_HI_rayleigh
    endif

    where(lambda > lambda_limit_lya)
        HI_rayleigh_part2 = (1d0 + (156.6d0/lambda)**2.d0 + &
            (148.d0/lambda)**4d0)*(96.6d0/lambda)**4d0
    elsewhere
    	HI_rayleigh_part2 = 0.0
    end where    
    
    return
  end subroutine init_HI_rayleigh_part2	

  subroutine HI_Rayleigh(id, icell, N, lambda, scatt)
    ! ------------------------------------------------------------- !
    ! Rayleigh scattering on neutral Hydrogen.
    ! Baschek & Scholz 1982
    ! ------------------------------------------------------------- !
    integer, intent(in)                                       :: icell, id, N
    real(kind=dp), dimension(N), intent(in) 					:: lambda
    real        											:: lambda_limit
    real(kind=dp), dimension(N), intent(out) 				:: scatt
    integer :: k

    scatt = 0d0

    where(lambda > lambda_limit_HI_rayleigh)
       scatt = (1d0 + (156.6d0/lambda)**2.d0 + &
            (148.d0/lambda)**4d0)*(96.6d0/lambda)**4d0
    end where


    scatt(:) =  scatt(:) * sigma_e * sum(Hydrogen%n(1:Hydrogen%Nlevel-1,icell))


    return
  end subroutine HI_Rayleigh
  
  function HeI_rayleigh_part1(icell)
    ! ------------------------------------------------------------- !
    ! He I Rayleigh scattering cross-section x nHeI.
    ! unit m^-1
    ! ------------------------------------------------------------- ! 	
    integer, intent(in) :: icell
  	real(kind=dp) :: HeI_rayleigh_part1
  	integer :: last_neutral_level
  	
  	!need to evaluate neutr_index only once.  	
  	!could be faster
	last_neutral_level = 1
    do while (Helium%stage(last_neutral_level) == 0)
       last_neutral_level = last_neutral_level+1
    enddo
    last_neutral_level = last_neutral_level - 1 !first (or first ion) continuum - 1

	!first ion - 1
! 	last_neutral_level = find_continuum(helium, 1) - 1
	if (helium%stage(last_neutral_level) /= 0.0) then
		write(*,*) "Helium as no neutral levels, sigHe = 0", last_neutral_level
		HeI_rayleigh_part1 = 0.0_dp
		return
	endif
  	
!   	HeI_rayleigh_part1 = sigma_e * sum(Helium%n(1:last_neutral_level,icell)) !m^-1
  	HeI_rayleigh_part1 = sigma_e * Helium%n(1,icell)!m^-1
  
  	return
  end function HeI_rayleigh_part1
  
  subroutine init_HeI_rayleigh_part2(N, Lambda, HeI_rayleigh_part2)
    ! ------------------------------------------------------------- !
    ! H I Rayleigh scattering cross-section.
    ! wavelength dependent term
    ! ------------------------------------------------------------- ! 
    integer, intent(in) :: N
    real(kind=dp), intent(in) :: Lambda(N)
    real(kind=dp), intent(out) :: HeI_rayleigh_part2(N)
    
    write(*,*) "*** Check limit for rayleigh scattering Helium  and ground state(s) (sigHe1, sigHe2) ***"

    where(lambda > lambda_limit_HeI_rayleigh)
       HeI_rayleigh_part2 = 4d0 * (1d0 + (66.9d0/lambda)**2.d0 + &
            (64.1d0/lambda)**4d0)*(37.9d0/lambda)**4d0
    elsewhere
    	HeI_rayleigh_part2 = 0.0
    end where    
    
    return
  end subroutine init_HeI_rayleigh_part2	

  subroutine HeI_Rayleigh(id, icell, N, lambda, scatt)
    ! ------------------------------------------------------------- !
    ! Rayleigh scattering on neutral Helium.
    ! Baschek & Scholz 1982

    ! ------------------------------------------------------------- !
    !type (AtomType), intent(in)                               :: atom
    integer, intent(in)                                       :: icell, id, N
    real(kind=dp), dimension(N), intent(in)					:: lambda
    real(kind=dp), dimension(N), intent(out) 				:: scatt
    integer													:: Neutr_index, l

    if (.not.associated(Helium)) return

    scatt = 0d0

    l = 1
    do while (Helium%stage(l)==0)
       l = l+1
    enddo
    Neutr_index = l - 1


    where(lambda > lambda_limit_HeI_rayleigh)
       scatt(:) = 4d0 * (1d0 + (66.9d0/lambda)**2.d0 + &
            (64.1d0/lambda)**4d0)*(37.9d0/lambda)**4d0
    end where


    scatt(:) = scatt(:) * sigma_e * sum(Helium%n(1:Neutr_index,icell)) !m^-1

    !
    return
  end subroutine HeI_Rayleigh

  ELEMENTAL function Gaunt_bf(u, n_eff)
    ! M. J. Seaton (1960), Rep. Prog. Phys. 23, 313
    ! See also Menzel & Pekeris 1935
    real(kind=dp), intent(in) :: n_eff,  u ! = n_Eff**2 * eps = hnu/Z/Z/E_RYDBERG - 1
    real(kind=dp) :: Gaunt_bf
    Gaunt_bf = 1d0 + 0.1728 * (n_eff**(-2./3.)) * (u+1d0)**(-2./3.) * (u-1d0) &
         - 0.0496*(n_eff**(-4./3.)) * (u+1d0)**(-4./3.) * (u*u + 4./3. * u + 1d0)

    !   if (Gaunt_bf <= 0d0 .or. Gaunt_bf > 2d0) then
    !    Gaunt_bf = 1d0
    !   end if

    ! need a proper extrapolation for when it is negative
    if (Gaunt_bf < 0.0) Gaunt_bf = 0.0
    if (Gaunt_bf > 2.0) Gaunt_bf = 1.0

    return
  end function Gaunt_bf


  Elemental function Gaunt_ff(lambda, Z, T)
    ! M. J. Seaton (1960), Rep. Prog. Phys. 23, 313
    !
    ! Note: There is a problem with this expansion at higher temperatures
    ! (T > 3.0E4 and longer wavelengths (lambda > 2000 nm). Set to
    ! 1.0 when the value goes below 1.0
    real(kind=dp),intent(in) :: lambda, T
    real(kind=dp) :: x, x3, y, Gaunt_ff
    integer, intent(in) :: Z

    x = ((HPLANCK * CLIGHT)/(lambda * NM_TO_M)) / &
         (E_RYDBERG * (Z)**(2d0))
    x3 = (x**(3.3333333d-1))
    y  = (2.0 * lambda * NM_TO_M * KBOLTZMANN*T) / &
         (HPLANCK*CLIGHT)

    gaunt_ff = 1.0 + 0.1728*x3 * (1.0 + y) - &
         0.0496*(x3*x3) * (1.0 + (1.0 + y)*0.33333333*y)

    if (gaunt_ff <= 0d0 .or. gaunt_ff > 2d0) gaunt_ff = 1d0

    return
  end function Gaunt_ff

  ELEMENTAL function  H_bf_Xsection(cont, lambda) result(alpha) !_lambda
    Type (AtomicContinuum), intent(in) :: cont
    real(kind=dp), intent(in) :: lambda
    real(kind=dp) :: n_eff, g_bf, u, Z, u0, g_bf0, alpha, u1


    Z = real(cont%atom%stage(cont%i) + 1,kind=dp)

    if (cont%atom%ID=='H') then
       n_eff = real(cont%i,kind=dp)
    else
       n_eff = Z*sqrt(cont%atom%Rydberg / (cont%atom%E(cont%j) - cont%atom%E(cont%i)))
    endif

    u = n_eff**2 * HPLANCK*CLIGHT / (NM_TO_M * lambda) / Z*Z / E_RYDBERG - 1
    u0 = n_eff*n_eff * HPLANCK*CLIGHT / (NM_TO_M * cont%lambda0) / Z / Z / E_RYDBERG - 1.

    g_bf = Gaunt_bf(u, n_eff)
!     g_bf0 = Gaunt_bf(u0, n_eff)

    !     if (lambda > cont%lambda0) then !linear  extrapolation of g_bf
    !       u1 = n_eff**2 * HPLANCK*CLIGHT / (NM_TO_M * 0.8 * cont%lambda0 ) / Z*Z / E_RYDBERG - 1
    !       g_bf = g_bf0 + (u - u1) / (u0 - u1) * (g_bf0 -  Gaunt_bf(u1, n_eff))
    !     endif

    !There is a factor n_eff/Z**2 absorbed in alpha0 beware
    !alpha = cont%alpha0 * (lambda/cont%lambda0)**3  * g_bf / g_bf0
    !alpha = n_eff/Z**2 * cont%alpha0 * (lambda/cont%lambda0)**3  * g_bf / g_bf0
    !1d-4* 2.815d29
    alpha = 2.815d25 * (Z**4) * g_bf / n_eff**5 * (NM_TO_M*lambda/CLIGHT)**3

    return
  end function H_bf_Xsection!_lambda

  subroutine  test_bf_xs(cont, lambda)
    !test the computation of hydrogenic bound-free cross-sections
    Type (AtomicContinuum), intent(in) :: cont
    real(kind=dp), intent(in) :: lambda
    real(kind=dp) :: n_eff, g_bf, u, Z, u0, g_bf0, alpha


    Z = real(cont%atom%stage(cont%i) + 1,kind=dp)
    !    if (cont%atom%ID == "H ") then
    !       n_eff = sqrt(Hydrogen%g(cont%i)/2.)  !only for Hydrogen !
    !       !n_eff = Z*sqrt(E_RYDBERG / (cont%atom%E(cont%j) - cont%atom%E(cont%i)))
    !    else
    !      !obtained_n = getPrincipal(metal%label(continuum%i), n_eff)
    !      !if (.not.obtained_n) &
    !      n_eff = Z*sqrt(E_RYDBERG / (cont%atom%E(cont%j) - cont%atom%E(cont%i)))
    !    end if
    n_eff = Z*sqrt(E_RYDBERG / (cont%atom%E(cont%j) - cont%atom%E(cont%i)))


    u = n_eff**2 * HPLANCK*CLIGHT / (NM_TO_M * lambda) / Z*Z / E_RYDBERG - 1
    u0 = n_eff*n_eff * HPLANCK*CLIGHT / (NM_TO_M * cont%lambda0) / Z / Z / E_RYDBERG - 1.

    g_bf = Gaunt_bf(u, n_eff)
    g_bf0 = Gaunt_bf(u0, n_eff)

    alpha = cont%alpha0 * (lambda/cont%lambda0)**3  * g_bf / g_bf0
    !alpha0 = 1d-4*2.815d29 * Z**4 * g_bf0 / n**5
    !alpha =1d-4* 2.815d29 * (Z**4) * g_bf /n_eff**5 * (NM_TO_M*lambda/CLIGHT)**3
    write(*,*) lambda, cont%lambda0, g_bf, g_bf0, n_eff
    write(*,*) alpha, 1d-4* 2.815d29 * (Z**4) * g_bf /n_eff**5 * (NM_TO_M*lambda/CLIGHT)**3
    return
  end subroutine test_bf_xs


  subroutine lte_bound_free(icell, N, lambda, chi, eta)
    integer, intent(in)											:: icell, N
    real(kind=dp), intent(in), dimension(N)						:: lambda
    real(kind=dp), intent(out), dimension(N)					:: chi, eta
    integer														:: m, kr, kc, i, j, la
    type (AtomType), pointer									:: atom
    real(kind=dp)												:: wj, wi, l_min, l_max, twohnu3_c2, n_eff
    real(kind=dp)												:: Diss, chi_ion, gij, alpha, ni_njgij

    chi = 0.0_dp
    eta = 0.0_dp

    do m=1, NpassiveAtoms
       atom => PassiveAtoms(m)%ptr_atom

       tr_loop : do kc=atom%Ntr_line+1,atom%Ntr
          kr = atom%at(kc)%ik

          if (.not.atom%at(kc)%lcontrib_to_opac) cycle tr_loop

          i = atom%continua(kr)%i
          j = atom%continua(kr)%j


          l_min = atom%continua(kr)%lambdamin
          l_max = atom%continua(kr)%lambdamax

		  !-> avoid real precision errors and discrepancy with nonlte_bf() which uses Nblue and Nred!
		  !(so the closest blue and red wavelengths on the grid and not exactly l_min/l_max)
          l_min = lambda(locate(lambda, l_min))
          l_max = lambda(locate(lambda, l_max))

          wj = 1.0; wi = 1.0

          if (ldissolve) then
             if (atom%ID=="H") then
                n_eff = real(i,kind=dp)
                wi = wocc_n(icell, n_eff, real(atom%stage(i)), real(atom%stage(j)), hydrogen%n(1,icell))
             else
                n_eff = atom%stage(j)*sqrt(atom%Rydberg/(atom%E(j)-atom%E(i)))
             endif
          endif

          chi_ion = Elements(atom%periodic_table)%ptr_elem%ionpot(atom%stage(j))


          do la=1, N
!              if ((lambda(la) < l_min).or.(lambda(la)>l_max)) cycle
			 if (lambda(la) < l_min) cycle
			 if (lambda(la) > l_max) exit

             !can be long depending on n_cells and N; but avoid storing
             !this on memory and it is computed only once.
             if (atom%continua(kr)%hydrogenic) then
                alpha = H_bf_Xsection(atom%continua(kr), lambda(la))
             else
!                 alpha = interp(atom%continua(kr)%alpha_file, atom%continua(kr)%lambda_file, lambda(la))
                alpha = interp1d_sorted(size(atom%continua(kr)%alpha_file), atom%continua(kr)%lambda_file, &
                						atom%continua(kr)%alpha_file, lambda(la))
             endif
             !!alpha = atom%continua(kr)%alpha(la)

             !1 if lambda <= lambda0
             Diss = D_i(icell, real(i,kind=dp), real(atom%stage(i)),1.0, lambda(la), atom%continua(kr)%lambda0, chi_ion)
             twohnu3_c2 = twohc/lambda(la)**3
             gij = atom%nstar(i,icell)/(atom%nstar(j,icell) + 1d-100) * exp(-hc_k/T(icell)/lambda(la))
             ni_njgij = atom%n(i,icell) - atom%n(j,icell) * gij

             if ( ni_njgij > 0.0) then

                chi(la) = chi(la) + Diss * alpha * ni_njgij

                eta(la) = eta(la) + Diss * alpha * twohnu3_c2 * gij * atom%n(j,icell)

             else !small inversions

                eta(la) = eta(la) + Diss * alpha * twohnu3_c2 * gij * atom%n(j,icell)
                chi(la) = chi(la) - diss*alpha*ni_njgij

             endif
          enddo
       enddo tr_loop
    end do ! loop over Ncont

    return
  end subroutine lte_bound_free



  function  H_ff_Xsection(Z, T, lambda) result(alpha) !ELEMENTAL
    real(kind=dp), intent(in) :: lambda, T
    real(kind=dp) :: g_ff, nu3, alpha, K0
    integer, intent(in) :: Z

    !    K0 = (Q_ELECTRON**2)/(4.0*PI*EPSILON_0) / sqrt(M_ELECTRON)
    !    K0 = (K0**3) * 4./3. * sqrt(2*pi/3./KBOLTZMANN) / HPLANCK / CLIGHT
    !sigma0_H_ff = K0

    nu3 = (NM_TO_M * lambda / CLIGHT)**3 ! = 1 / nu**3

    g_ff = Gaunt_ff(lambda, Z, T)

    alpha =  sigma0_H_ff * real(Z) * real(Z) * nu3 * g_ff / sqrt(T)

    !write(*,*) "alphaff", alpha, sigma0_H_ff, g_ff, T, nu3

    return
  end function H_ff_Xsection

!!!! Landi Degl'Innocenti 1976, A&ASS, 25, 379
  ! 	elemental function hydrogen_ff_bf(icell,T, lambda_in) result(hydro) !m^2, lambda_in in AA
  ! 	integer, intent(in) :: icell
  ! 	real(kind=8) :: hydro
  ! 	real(kind=8), intent(in) :: T, lambda_in
  ! 	real(kind=8) :: r, c1, c2, cte, theta1, theta2, theta3, sum, gff
  ! 	integer :: i, n0
  !
  ! 		r = 1.096776d-3
  ! 		c1 = 1.5777216d5
  ! 		c2 = 1.438668d8
  ! 		cte = 1.045d-26
  !
  ! 		theta1 = c1 / T
  ! 		theta2 = c2 / (lambda_in * T)
  ! 		theta3 = 2.d0*theta1
  !
  ! Lowest level which can be photoionized
  ! 		n0 = 1 + floor(sqrt(r*lambda_in))
  !
  ! Sum over states that can be photoionized
  ! 		if (n0 <= 8) then
  ! 			sum = exp(theta1 / n0**2) / n0**3
  ! 			do i = n0+1, 8
  ! 				sum = sum + exp(theta1 / i**2) / i**3
  ! 			enddo
  ! 			sum = sum + (0.117d0 + exp(theta1/81.d0)) / theta3
  ! 		else
  ! 			sum = (0.117d0 + exp(theta1/n0**2)) / theta3
  ! 		endif
  !
  ! Approximate the value of the Gaunt factor G_ff from Mihalas Eq (80) @ theta=1, x=0.5
  ! 		gff = (1.d0-exp(-theta2)) * exp(-theta1) * lambda_in**3
  !
  ! 		hydro = cte * gff * sum * 1e-4 * nHtot(icell)!m^2
  !
  ! 	end function hydrogen_ff_bf

  !To do, add contributions from dissolve states to dissolve states
  subroutine Hydrogen_ff(icell, N, lambda, chi)
    ! Hubeny & Mihalas eq. 7.100 (from cgs to SI)
    ! takes place at LTE because it is collisional
    integer, intent(in) :: icell, N
    real(kind=dp), intent(in), dimension(N) :: lambda
    integer :: la
    real(kind=dp), dimension(N), intent(out) :: chi
    real(kind=dp) :: stim, np, arg_exp, exp_val, C0, alpha

    np = Hydrogen%n(Hydrogen%Nlevel,icell) !nH+=Nion H
    !should be nstar instead of %n ?

    chi(:) = 0d0

    if (ne(icell) == 0d0) return


    do la=1,N
       stim = 1. - exp(-hc_k/lambda(la)/T(icell))

       ! = alpha0 /nu**3 / sqrt(T) = m^5
       !I now consider ne as part of the cross-sections to be in the same units as
       !the bound-free cross-sections
       alpha = H_ff_Xsection(1, T(icell), lambda(la)) * ne(icell)


       chi(la) =  alpha * np * stim

    enddo


    return
  end subroutine Hydrogen_ff

  !! building
  !  subroutine atom_ff_transitions(atom, icell, chi)
  !  Hubeny & Mihalas eq. 7.100 (from cgs to SI)
  !  takes place at LTE because it is collisional
  !  should work with Hydrogen
  !   integer, intent(in) :: icell
  !   type (AtomType), intent(in) :: atom
  !   real(kind=dp), dimension(NLTEspec%Nwaves), intent(out) :: chi
  !   real(kind=dp) :: stim, nion, arg_exp, exp_val
  !   integer :: ic, Z, la
  !
  !  chi(:) = 0d0
  !  if (ne(icell)==0d0) return
  !
  !  ic = atom%Nlevel
  !  Z = atom%stage(ic)
  !
  !  nion = atom%n(ic, icell)
  !
  !  do la=1,NLTEspec%Nwaves
  !
  !     stim = 1.- exp(-hc_k/NLTEspec%lambda(la)/T(icell))
  !
  !     chi(la) = H_ff_Xsection(Z, T(icell), NLTEspec%lambda(la)) * nion * stim * ne(icell)
  !
  !  enddo
  !
  !
  !  return
  !  end subroutine atom_ff_transitions




  subroutine Hminus_bf(icell, N, lambda, chi, eta)
    !-----------------------------------------------------------------
    ! Calculates the negative hydrogen (H-) bound-free continuum
    ! absorption coefficient per
    ! hydrogen atom in the ground state from
    !  John 1988 A&A 193, 189
    ! Includes stimulated emission
    !-----------------------------------------------------------------
    integer, intent(in) :: icell, N
    real(kind=dp), intent(in), dimension(N) :: lambda
    real(kind=dp) :: lam, lambda0, alpha, sigma, flambda, Cn(6)
    real(kind=dp) :: diff, stm, funit, cte, pe
    integer :: la
    real(kind=dp) :: arg_exp, nH
    real(kind=dp), dimension(N), intent(out) :: chi, eta

    chi(:) = 0.0_dp
    eta(:) = 0.0_dp

    !1dyne/cm2 = 1e-1 Pa
    !1dyne = 1e-1 Pa cm2
    !cm4/dyne = cm4 / (1e-1 Pa cm2)
    !cm4/dyne = 10 * cm2 / Pa
    !cm4/dyne = 10 * (1e-2)**2 m2/Pa = 1e-3 * m2/Pa
    !m2/Pa = cm4/dyne  * 1e3
    funit = 1d-3 !m2/Pa -> cm2/dyn

    pe = ne(icell) * KBOLTZMANN * T(icell) !nkT in Pa

    Cn(:) = (/152.519d0,49.534d0,-118.858d0,92.536d0,-34.194d0,4.982d0/)

    alpha = hc_k / MICRON_TO_NM ! hc_k = hc/k/nm_to_m
    lambda0 = 1.6419 !micron, photo detachement threshold

    nH = hydrogen%n(1,icell)

    !alpha = hc_k / micron_to_nm * nm_to_m
    cte = 0.75d-18 * T(icell)**(-2.5) * exp(alpha/lambda0/T(icell)) * pe * funit * nH


    do la=1, N

       lam = lambda(la) / MICRON_TO_NM !nm->micron
       !if (lambda > 0.125 .and. lambda < lambda0) then
       if (lam <= lambda0) then

          diff = (1d0/lam - 1d0/lambda0)

          stm = 1. - exp(-alpha/lam/T(icell))

          flambda = Cn(1) + Cn(2) * diff**(0.5) + Cn(3) * diff + Cn(4) * diff**(1.5) + &
               Cn(5)*diff**(2.) + Cn(6) * diff**(2.5)

          sigma = lam**3d0 * diff**(1.5) * flambda !cm2
          chi(la) = cte * stm * sigma! m^-1
          !exp(-hnu/kt) * 2hnu3/c2 = Bp * (1.-exp(-hnu/kt))
          eta(la) = cte * (1.-stm) * sigma * twohc/lambda(la)**3

       endif

    enddo



    return
  end subroutine Hminus_bf


  subroutine Hminus_bf_geltman(icell, N, lambda, chi, eta)
    !-----------------------------------------------------------------
    ! Calculates the negative hydrogen (H-) bound-free continuum
    ! absorption coefficient per
    ! H minus atom from Geltman 1962, ApJ 136, 935-945
    ! Stimulated emission included
    !-----------------------------------------------------------------
    integer, intent(in) :: icell, N
    real(kind=dp), dimension(N), intent(in) :: lambda
    integer :: la
    real(kind=dp), intent(out), dimension(N) :: chi, eta
    integer, parameter :: NBF=34
    real(kind=dp), dimension(NBF) :: lambdaBF, alphaBF
    real(kind=dp) :: lam, stm, twohnu3_c2, alpha

    data lambdaBF / 0.0, 50.0, 100.0, 150.0, 200.0, 250.0,  &
         300.0, 350.0, 400.0, 450.0, 500.0, 550.0,&
         600.0, 650.0, 700.0, 750.0, 800.0, 850.0,&
         900.0, 950.0, 1000.0, 1050.0, 1100.0,    &
         1150.0, 1200.0, 1250.0, 1300.0, 1350.0,  &
         1400.0, 1450.0, 1500.0, 1550.0, 1600.0,  &
         1641.9 /

    !in 1e-21
    data alphaBF / 0.0,  0.15, 0.33, 0.57, 0.85, 1.17, 1.52,&
         1.89, 2.23, 2.55, 2.84, 3.11, 3.35, 3.56,&
         3.71, 3.83, 3.92, 3.95, 3.93, 3.85, 3.73,&
         3.58, 3.38, 3.14, 2.85, 2.54, 2.20, 1.83,&
         1.46, 1.06, 0.71, 0.40, 0.17, 0.0 /
    
!     chi = 1d-21 * linear_1D_Sorted(NBF,lambdaBF,alphaBF,N,lambda) * nHmin(icell)
!     eta = chi * twohc / lambda**3 * exp(-hc_k/T(icell)/lambda)
!     chi = chi * (1.0 - exp(-hc_k/T(icell)/lambda))

    chi = 0d0
    eta = 0d0
    
    do la=1, N
       lam = lambda(la)
       !do not test negativity of lambda
       if (lam >= lambdaBF(NBF)) exit

       stm = exp(-hc_k/T(icell)/lam)
       twohnu3_c2 = twohc / lam**3.

       alpha = 1d-21 * interp1D(lambdaBF*1d0, alphaBF*1d0, lam)  !1e-17 cm^2 to m^2

       chi(la) = nHmin(icell) * (1.-stm) * alpha
       eta(la) = nHmin(icell) * twohnu3_c2 * stm * alpha

    enddo


    return
  end subroutine Hminus_bf_geltman

  subroutine Hminus_bf_Wishart(icell, N, lambda, chi, eta)
    !The one use in Turbospectrum, number 1 in opacity
    !-----------------------------------------------------------------
    ! Calculates the negative hydrogen (H-) bound-free continuum
    ! absorption coefficient per
    ! H minus atom from Wishart A.W., 1979, MNRAS 187, 59P
    !-----------------------------------------------------------------
    integer, intent(in) :: icell, N
    integer :: la
    real(kind=dp), dimension(N), intent(in)	:: lambda
    real(kind=dp), dimension(N), intent(out) :: chi, eta
    !    real, dimension(36) :: lambda, alpha
    real, dimension(63) :: lambdai, alphai
    real(kind=dp) :: lam, stm, sigma, chi_extr(1), eta_extr(1), lambda_extr(1)

    chi(:) = 0.0_dp
    eta(:) = 0.0_dp

    !    data lambda / 0.00,1250.00 ,  1750.00  , 2250.70  , 2750.81  , 3250.94,&
    !    3751.07  , 4251.20  , 4751.33   ,5251.46 ,  5751.59 ,  6251.73, &
    !    6751.86  , 7252.00  , 7752.13  , 8252.27  , 8752.40   ,9252.54,&
    !    9752.67 ,  10252.81  ,10752.95 , 11253.08 , 11753.22 , 12253.35,&
    !   12753.49  ,13253.62 , 13753.76 , 14253.90 , 14754.03  ,15254.17,&
    !   15504.24 , 15754.30  ,16004.37 , 16104.40 , 16204.43 , 16304.45 /

    !1d-18 cm^2 * (1d-2)**2 for m^2 = 1d-22
    !   data alpha /0.0  ,     5.431 ,    7.918    , 11.08  ,   14.46   ,  17.92, &
    !      21.35 ,    24.65   ,  27.77  ,   30.62   ,  33.17   ,  35.37,&
    !      37.17  ,   38.54  ,   39.48  ,   39.95   ,  39.95 ,    39.48,&
    !      38.53  ,   37.13 ,   35.28  ,   33.01 ,    30.34     ,27.33,&
    !      24.02  ,   20.46   ,  16.74   ,  12.95  ,   9.211   ,  5.677,&
    !      4.052 ,    2.575 ,    1.302   ,  .8697    , .4974   ,  .1989 /

    data lambdai / 250, 1500, 1750, 2000, 2250, 2500, 2750, 3000, 3250, 3500, 3750,      &
         4000, 4250, 4500, 4750, 5000, 5250, 5500, 5750, 6000, 6250, 6500,     &
         6750, 7000, 7250, 7500, 7750, 8000, 8250, 8500, 8750, 9000, 9250,     &
         9500, 9750, 10000, 10250, 10500, 10750, 11000, 11250, 11500, 11750,   &
         12000, 12250, 12500, 12750, 13000, 13250, 13500, 13750, 14000,        &
         14250, 14500, 14750, 15000, 15250, 15500, 15750, 16000, 16100, 16200, &
         16300 /

    data alphai / 5.431, 6.512, 7.918, 9.453, 11.08,12.75,14.46,16.19,17.92,19.65,21.35,   &
         23.02,24.65,26.24, 27.77, 29.23,30.62,31.94,33.17,34.32, 35.37,36.32,    &
         37.17,37.91,38.54,39.07,39.48,39.77,39.95, 40.01, 39.95, 39.77, 39.48,   &
         39.06,38.53,37.89,37.13,36.25,35.28,34.19,33.01,31.72,30.34,28.87,       &
         27.33,25.71,24.02,22.26,20.46,18.62,16.74,14.85,12.95,11.07,9.211,7.407, &
         5.677,4.052,2.575,1.302,0.8697,0.4974, 0.1989 /

    freq_loop : do la=1, N
       lam = lambda(la) * 10. !AA
       !stm = 0.0
       stm = exp(-hc_k / T(icell) / lambda(la))

       !if (lam < minval(lambdai)) then
       if (lam < lambdai(1)) then
          !cyle
          !other formula for very low frequencies
          lambda_extr(1) = lambda(la)
          call Hminus_bf_geltman(icell, 1, lambda_extr, chi_extr, eta_extr)
          chi(la) = chi_extr(1)
          eta(la) = eta_extr(1)
          !cycle
          !else if (lam > maxval(lambdai)) then
       elseif (lam > lambdai(63)) then
          exit freq_loop
       else

          sigma = 1d-22 * interp1D(lambdai*1d0, alphai*1d0, lam) * nHmin(icell)
          !beware linear_1D_sorted doesn't handle well the values out of bounds (y(xi>x) = 0 not y(x))
          !!sigma(:) = linear_1D_Sorted(63,lambdai*1.0_dp,alphai*1.0_dp,1,lam) ;*1d-22*sigma(1)
          chi(la) = sigma * (1.0 - stm)
          eta(la) = sigma * twohc/lambda(la)**3  * stm

       endif
    enddo freq_loop


    return
  end subroutine Hminus_bf_Wishart

  ! !fit to the best data
  ! produce a spurious pik close to 188nm
  function Hminus_ff_john(icell, lambda) result(chi)
    !-----------------------------------------------------------------
    ! Calculates the negative hydrogen (H-) free-free continuum
    ! absorption coefficient per
    ! hydrogen atom in the ground state from John 1988
    !-----------------------------------------------------------------
    integer, intent(in) :: icell
    real(kind=dp), intent(in) :: lambda
    !tab. 3a, lambda > 0.3645micron
    real(kind=dp), dimension(6) :: An, Bn, Cn, Dn, En, Fn
    !tab 3b, lambda > 0.1823 micron and < 0.3645 micron, size of 4 isntead 5, because the last two rows are 0
    real(kind=dp), dimension(4) :: An2, Bn2, Cn2, Dn2, En2, Fn2
    real(kind=dp) :: funit, K, kappa
    integer :: la, n
    real(kind=dp) :: chi
    real(kind=dp) :: lam, theta, nH

    chi = 0.0
    theta = 5040d0 / T(icell)
    lam = lambda / MICRON_TO_NM

    if (theta < 0.5 .or. theta > 3.6) return
    if (lam <= 0.1823) return

    An = (/0.d0,2483.346d0,-3449.889d0,2200.04d0,-696.271d0,88.283d0/)
    Bn = (/0.d0,285.827d0,-1158.382d0,2427.719d0,-1841.4d0,444.517d0/)
    Cn = (/0.d0,-2054.291d0,8746.523d0,-13651.105d0,8624.97d0,-1863.864d0/)
    Dn = (/0.d0,2827.776d0,-11485.632d0,16755.524d0,-10051.53d0,2095.288d0/)
    En = (/0.d0,-1341.537d0,5303.609d0,-7510.494d0,4400.067d0,-901.788d0/)
    Fn = (/0.d0,208.952d0,-812.939d0,1132.738d0,-655.02d0,132.985d0/)
    An2 = (/518.1021d0,473.2636d0,-482.2089d0,115.5291d0/)
    Bn2 = (/-734.8666d0,1443.4137d0,-737.1616d0,169.6374d0/)
    Cn2 = (/1021.1775d0,-1977.3395d0,1096.8827d0,-245.649d0/)
    Dn2 = (/-479.0721d0,922.3575d0,-521.1341d0,114.243d0/)
    En2 = (/93.1373d0,-178.9275d0,101.7963d0,-21.9972d0/)
    Fn2 = (/-6.4285d0,12.36d0,-7.0571d0,1.5097d0/)

    funit = 1d-3 !cm4/dyne to m2/Pa
    nH = hydrogen%n(1,icell)

    K = 1d-29 * funit * ne(icell) * KBOLTZMANN * T(icell) * nH


    kappa = 0.0_dp
    if (lam < 0.3645) then
       do n=1,4
          kappa = kappa + theta**((n+1)/2d0) * (lam**2 * An2(n) + Bn2(n) + Cn2(n)/lam + &
               Dn2(n)/lam**2 + En2(n)/lam**3 + Fn2(n)/lam**4)
       enddo
    else! if (lambda > 0.3645) then
       do n=1,6
          kappa = kappa + theta**((n+1)/2d0) * (lam**2 * An(n) + Bn(n) + Cn(n)/lam + &
               Dn(n)/lam**2 + En(n)/lam**3 + Fn(n)/lam**4)
       enddo
    endif
    chi = kappa * K


    return
  end function Hminus_ff_John

  ! !fit to the best data
  ! produce a spurious pik close to 188nm
  subroutine Hminus_ff(icell, N, lambda, chi)
    !-----------------------------------------------------------------
    ! Wrapper around Hminus_ff_john
    !-----------------------------------------------------------------
    integer, intent(in) :: icell, N
    real(kind=dp), dimension(N), intent(in) :: lambda
    integer :: la
    real(kind=dp), dimension(N), intent(out) :: chi
    real(kind=dp) :: lam, theta!, nH

    chi(:) = 0.0_dp

    theta = 5040d0 / T(icell)

    if (theta < 0.5 .or. theta > 3.6) return

    do la=1, N
       chi(la) = Hminus_ff_john(icell, lambda(la))
    enddo

    return
  end subroutine Hminus_ff

  subroutine Hminus_ff_bell_berr(icell, N, lambda, chi)
    !-----------------------------------------------------------------
    ! Calculates the negative hydrogen (H-) free-free continuum
    ! absorption coefficient per
    ! hydrogen atom in the ground state from
    ! Bell & Berrington 1986, J. Phys. B 20, 801
    !
    ! at long wavelength Hminus_ff_john is used.
    !
    !-----------------------------------------------------------------
    !stm is already included

    integer, intent(in) :: icell, N
    real(kind=dp), dimension(N), intent(in) :: lambda
    integer :: la
    real(kind=dp), dimension(N), intent(out) :: chi
    real, dimension(:) :: lambdai(23), thetai(11)
    real, dimension(23,11) :: alphai
    real :: inter
    real(kind=dp) :: lam, stm, sigma, theta, pe, nH

    chi(:) = 0.0_dp
    theta = 5040. / T(icell)

    if (theta < 0.5 .or. theta > 3.6) then
       !return
       if (theta < 0.5) theta = 0.5_dp
       if (theta > 3.6) theta = 3.6_dp
    endif

    !AA, index 12 (11 in C) is 9113.0 AA
    data lambdai  /0.00, 1823.00, 2278.0, 2604.0, 3038.0, 3645.0,			&
         4557.0, 5063.0, 5696.0, 6510.0, 7595.0, 9113.0, 					&
         10126.0, 11392.0, 13019.0, 15189.0, 18227.0, 22784.0,				&
         30378.0, 45567.0, 91134.0, 113918.0, 151890.0						/

    data thetai /0.5, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.8, 3.6		/

    !1d-26 cm^4/dyn = 1d-26 * 1d-3 m^2 / Pa = 1d-29 m^2/Pa
    !t = 0.5
    data alphai(:,1) /0.0, 1.78e-2, 2.28e-2, 2.77e-2, 3.64e-2, 5.20e-2,		&
         7.91e-2, 9.65e-2, 1.21e-1, 1.54e-1, 2.08e-1, 2.93e-1,			&
         3.58e-1, 4.48e-1, 5.79e-1, 7.81e-1, 1.11, 1.73,					&
         3.04, 6.79, 2.70e1, 4.23e1, 7.51e1								/
    !t = 0.6
    data alphai(:,2) /0.0, 2.22e-2, 2.80e-2, 3.42e-2, 4.47e-2, 6.33e-2,		&
         9.59e-2, 1.17e-1, 1.46e-1, 1.88e-1, 2.50e-1, 3.54e-1, 4.32e-1,	&
         5.39e-1, 6.99e-1, 9.40e-1, 1.34, 2.08, 3.65, 8.16, 3.24e1,		&
         5.06e1, 9.0e1													/
    !t = 0.8
    data alphai(:,3) /0.0, 3.08e-2, 3.88e-2, 4.76e-2, 6.16e-2, 8.59e-2,		&
         1.29e-1, 1.57e-1, 1.95e-1, 2.49e-1, 3.32e-1, 4.68e-1, 5.72e-1,	&
         7.11e-1, 9.24e-1, 1.24, 1.77, 2.74, 4.80, 1.07e1, 4.26e1, 		&
         6.64e1, 1.18e2													/
    !t = 1.0
    data alphai(:,4) /0.0, 4.02e-2, 4.99e-2, 6.15e-2, 7.89e-2, 1.08e-1,		&
         1.61e-1, 1.95e-1, 2.41e-1, 3.09e-1, 4.09e-1, 5.76e-1, 7.02e-1,		&
         8.71e-1, 1.13, 1.52, 2.17, 3.37, 5.86, 1.31e1, 5.19e1, 8.08e1,		&
         1.44e2																/
    !t = 1.2
    data alphai(:,5) /0.0, 4.98e-2, 6.14e-2, 7.60e-2, 9.66e-2, 1.31e-1,		&
         1.94e-1, 2.34e-1, 2.88e-1, 3.67e-1, 4.84e-1, 6.77e-1, 8.25e-1, 	&
         1.02, 1.33, 1.78, 2.53, 3.90, 6.86, 1.53e1, 6.07e1, 9.45e1,		&
         1.68e2															/
    !t = 1.4
    data alphai(:,6) /0.0, 5.96e-2, 7.32e-2, 9.08e-2, 1.14e-1, 1.54e-1, 	&
         2.27e-1, 2.72e-1, 3.34e-1, 4.24e-1, 5.57e-1, 7.77e-1, 9.43e-1, 	&
         1.16, 1.51, 2.02, 2.87, 4.50, 7.79, 1.74e1, 6.89e1, 1.07e2, 	&
         1.91e2															/
    !t = 1.6
    data alphai(:,7) /0.0, 6.95e-2, 8.51e-2, 1.05e-1, 1.32e-1, 1.78e-1, 	&
         2.60e-1, 3.11e-1, 3.81e-1, 4.82e-1, 6.30e-1, 8.74e-1, 1.06,		&
         1.29, 1.69, 2.26, 3.20, 5.01, 8.67, 1.94e1, 7.68e1, 1.20e2, 	&
         2.12e2															/

    !t = 1.8
    data alphai(:,8) /0.0, 7.95e-2, 9.72e-2, 1.21e-1, 1.50e-1, 2.01e-1, 	&
         2.93e-1,3.51e-1, 4.28e-1, 5.39e-1, 7.02e-1,9.69e-1,1.17, 1.43, 	&
         1.86,2.48, 3.51,5.50, 9.50, 2.12e1, 8.42e1, 1.31e2, 2.34e2		/

    !t = 2.0
    data alphai(:,9) /0.0, 8.96e-2, 1.1e-1, 1.36e-1, 1.69e-1, 2.25e-1, 		&
         3.27e-1, 3.9e-1, 4.75e-1, 5.97e-1, 7.74e-1, 1.06, 1.28, 1.57, 	&
         2.02, 2.69, 3.8, 5.95, 1.03e1, 2.30e1, 9.14e1, 1.42e2, 2.53e2	/

    !t = 2.8
    data alphai(:,10) /0.0, 1.31e-1, 1.60e-1, 1.99e-1, 2.43e-1, 3.21e-1, 	&
         4.63e-1, 5.49e-1, 6.67e-1, 8.30e-1, 1.06, 1.45, 1.73, 2.09, 	&
         2.67, 3.52, 4.92, 7.59, 1.32e1, 2.95e1, 1.17e2, 1.83e2, 		&
         3.25e2															/

    !t = 3.6
    data alphai(:,11) /0.0, 1.72e-1, 2.11e-1, 2.62e-1, 3.18e-1, 4.18e-1,	&
         6.02e-1, 7.11e-1, 8.61e-1, 1.07, 1.36, 1.83, 2.17, 2.60, 3.31, 	&
         4.31, 5.97, 9.06, 1.56e1, 3.50e1, 1.40e2, 2.19e2, 3.88e2		/


    pe = ne(icell) * KBOLTZMANN * T(icell)
    nH = hydrogen%n(1,icell)
    !    if (icell==66) write(*,*) pe, nH

    do la=1, N
       lam = lambda(la) * 10.
       if (lam > lambdai(23)) then
          chi(la) = Hminus_ff_john(icell,lambda(la))
       else
          stm = exp(-hc_k/T(icell)/lambda(la))
          sigma = 1d-29 * interp2D(lambdai*1d0,thetai*1d0,1d0*alphai,lam,theta) !m^2/Pa
          !Need bi-linear interpolation
          chi(la) = sigma * pe * nH!m^-1
       endif
       ! 	 if (icell==66) then
       ! 	 	write(*,*) lambda(la), chi(la), sigma, stm
       ! 	 endif
    enddo
    ! if (icell==66) stop
    return
  end subroutine Hminus_ff_bell_berr


end module background_opacity

!  subroutine Hminus_ff_bell_berr(icell, N, lambda, chi)
!  !-----------------------------------------------------------------
!  ! Calculates the negative hydrogen (H-) free-free continuum
!  ! absorption coefficient per
!  ! hydrogen atom in the ground state from
!  ! Bell & Berrington 1986, J. Phys. B 20, 801
!  !
!  ! at long wavelength Hminus_ff_john is used.
!  !
!  !-----------------------------------------------------------------
!  !number 19 in turbospectrum opacities
!  !stm is already included
!
!    integer, intent(in) :: icell, N
!    real(kind=dp), dimension(N), intent(in) :: lambda
!    integer :: la
!    real(kind=dp), dimension(N), intent(out) :: chi
!    real, dimension(:) :: lambdai(24), thetai(10)
!    real, dimension(24,10) :: alphai
!    real :: inter
!    real(kind=dp) :: lam, stm, sigma, theta, pe, nH
!
!    chi(:) = 0.0_dp
!    theta = 5040. / T(icell)
!
!    if (theta < 0.5 .or. theta > 2.) then
!    	!return
!    	if (theta < 0.5) theta = 0.5_dp
!    	if (theta > 2.0) theta = 2.0_dp
!    endif
!
!    !AA
!    data lambdai  /0.00,   1823.00,   2278.70 ,  2604.78 ,  3038.88,   3646.04, &
!      4558.28 ,  5064.41 ,  5697.58 ,  6511.80 ,  7597.09  , 9115.50, &
!   10128.78,  11395.12 , 13022.56 , 15193.15 , 18231.98 , 22790.22,&
!   30386.29 , 45579.43 , 91158.84, 151931.41,  320000.0, 2100000.0 /
!
!    data thetai / 0.5  , 0.6  , 0.7  ,0.8 , 1.0 ,1.2, 1.4  ,1.6,1.8,2.0 /
!
!   !1d-26 cm^4/dyn = 1d-26 * 1d-3 m^2 / Pa = 1d-29 m^2/Pa
!    data alphai(:,1) /0.0 ,.0178 ,.0228,.0277,.0364,.0520, &
!      .0791 ,.0965    , 0.121     ,0.154     ,0.208  ,   0.293,&
!      0.358  ,   0.448  ,   0.579   ,  0.781    ,  1.11    ,  1.73,&
!       3.04  ,    6.79  ,    27.0    ,  75.1  ,  333.15  ,14347.73 /
!
!    data alphai(:,2) /     0.0    ,   .0222  ,   .0280  ,   .0342   ,  .0447   ,  .0633,&
!      .0959  ,   0.117,     0.146 ,    0.188   ,  0.250  ,   0.354,&
!      0.432 ,    0.539  ,   0.699  ,   0.940  ,    1.34   ,   2.08,&
!       3.65   ,   8.16  ,    32.4   ,   90.0  ,  399.25 , 17194.76 /
!
!    data alphai(:,3) / 0.0,.0265 ,.0334 ,.0409 , .0532 ,.0746 ,&
!      .112,.137 ,.171 ,.219 , .291 ,   .411 ,&
!      .502 ,.625,.812 ,1.09, 1.56, 2.41 ,&
!      4.23,9.43, 37.5, 104. ,461.36, 19869.04/
!
!    data alphai(:,4) / 0.0 ,.0308 ,.0388,.0476, .0616,.0859 ,&
!      0.129,0.157,0.195 , 0.249, 0.332,0.468 ,&
!      0.572 ,0.711, 0.924   ,   1.24  ,    1.77   ,   2.74 ,&
!       4.80  ,   10.7   ,   42.6   ,   118.    ,523.46 , 22543.71/
!
!    data alphai(:,5) /  0.0    ,   .0402   ,  .0499   ,  .0615    , .0789   ,  0.108 ,&
!      0.161   ,  0.195   ,  0.241   ,  0.309  ,   0.409    , 0.576 ,&
!      0.702  ,   0.871    ,  1.13    ,  1.52    ,  2.17     , 3.37 ,&
!       5.86  ,    13.1    ,  51.9    ,  144.  ,  638.80 , 27510.95/
!
!    data alphai(:,6) / 0.0   ,    .0498   ,  .0614    , .0760 ,    .0966 ,    0.131 ,&
!      0.194  ,   0.234 ,    0.288   ,  0.367 ,    0.484  ,   0.677 ,&
!      0.825   ,   1.02   ,   1.33    ,  1.78 ,     2.53   ,   3.90 ,&
!       6.86   ,   15.3   ,   60.7    ,  168.   , 745.27 , 32096.12/
!
!    data alphai(:,7) /  0.0    ,   .0596    , .0732 ,    .0908  ,   0.114   ,  0.154 ,&
!      0.227   ,  0.272   ,  0.334   ,  0.424 ,    0.557 ,    0.777 ,&
!      0.943 ,     1.16  ,    1.51    ,  2.02   ,   2.87  ,    4.50 ,&
!       7.79   ,   17.4 ,     68.9   ,   191.   , 847.30  ,36490.24/
!
!    data alphai(:,8) / 0.0    ,   .0695    , .0851   ,  0.105  ,   0.132  ,   0.178 ,&
!      0.260   ,  0.311 ,    0.381   ,  0.482     ,0.630   ,  0.874 ,&
!       1.06  ,    1.29 ,     1.69  ,    2.26   ,   3.20  ,    5.01 ,&
!       8.67    ,  19.4    ,  76.8  ,    212.   , 940.46 , 40502.25/
!
!    data alphai(:,9) /0.0    ,   .0795  ,  .0972   ,  0.121    , 0.150   ,  0.201 ,&
!      0.293   ,  0.351 ,    0.428   ,  0.539  ,   0.702    , 0.969 ,&
!       1.17 ,     1.43   ,   1.86    ,  2.48  ,    3.51    ,  5.50 ,&
!       9.50   ,   21.2  ,   84.2    ,  234.  , 1038.05 , 44705.31/
!
!    data alphai(:,10) /0.0   ,    .0896  ,   0.110 ,    0.136   ,  0.169   ,  0.225 ,&
!      0.327   ,  0.390  ,   0.475 ,    0.597 ,    0.774     , 1.06 ,&
!       1.28   ,   1.57  ,    2.02     , 2.69    ,  3.80    ,  5.95 ,&
!       10.3  ,    23.0    ,  91.4    ,  253. ,  1122.34 , 48335.22/
!
!
!    pe = ne(icell) * KBOLTZMANN * T(icell)
!    nH = hydrogen%n(1,icell)
! !    if (icell==66) write(*,*) pe, nH
!
!    do la=1, N
!      lam = lambda(la) * 10.
!      if (lam > lambdai(24)) then
!       chi(la) = Hminus_ff_john(icell,lambda(la))
!      else
!       stm = exp(-hc_k/T(icell)/lambda(la))
!       sigma = 1d-29 * interp2D(lambdai*1d0,thetai*1d0,1d0*alphai,lam,theta) !m^2/Pa
!       chi(la) = sigma * pe * nH!m^-1
!      endif
! ! 	 if (icell==66) then
! ! 	 	write(*,*) lambda(la), chi(la), sigma, stm
! ! 	 endif
!    enddo
! ! if (icell==66) stop
!  return
!  end subroutine


! Interpolation to the best data
!  subroutine Hminus_ff_longwavelength(icell, chi)
!  H- free-free opacity for wavelength beyond 9113.0 nm
!  see: T. L. John (1988), A&A 193, 189-192 (see table 3a).
!  His results are based on calculations by K. L. Bell and
!  K. A. Berrington (1987), J. Phys. B 20, 801-806.
!   integer :: k, n
!   integer, intent(in) :: icell
!   real(kind=dp), intent(inout), dimension(NLTEspec%Nwaves) :: chi
!   real(kind=dp), dimension(NJOHN) :: AJ, BJ, CJ, DJ, EJ, FJ
!   real(kind=dp), dimension(NJOHN,NLTEspec%Nwaves) :: Clam
!   real(kind=dp), dimension(NLTEspec%Nwaves) :: lambda_mu, lambda_inv
!   real(kind=dp) :: sqrt_theta, theta_n, CK
!
!   data AJ / 0.000,  2483.346, -3449.889,  2200.040, -696.271, 88.283   /
!   data BJ / 0.000,   285.827, -1158.382,  2427.719,-1841.400, 444.517  /
!   data CJ / 0.000, -2054.291,  8746.523,-13651.105,8624.970, -1863.864 /
!   data DJ / 0.000,2827.776,-11485.632, 16755.524,-10051.530, 2095.288  /
!   data EJ / 0.000, -1341.537,  5303.609, -7510.494,4400.067,  -901.788 /
!   data FJ / 0.000,   208.952,  -812.939,  1132.738, -655.020, 132.985  /
!
!   chi = 0d0
!
!   CK= (KBOLTZMANN * THETA0 * 1.0E-32);
!
!   lambda_mu = NLTEspec%lambda / MICRON_TO_NM
!   lambda_inv = 1. / lambda_mu
!
!   do n=1,NJOHN
!    Clam(n,:) = (lambda_mu)**2 * AJ(n) + BJ(n) + lambda_inv * &
!     (CJ(n) + lambda_inv*(DJ(n) + lambda_inv*(EJ(n) + &
!       lambda_inv*FJ(n))))
!   end do
!
!   theta_n = 1.
!   sqrt_theta = sqrt(THETA0/T(icell))
!   do n=2,NJOHN
!     theta_n = theta_n * sqrt_theta
!     chi = chi + theta_n * Clam(n,:)
!   end do
!   chi= chi* Hydrogen%n(1,icell) * (ne(icell)*CK)
!
!  return
!  end subroutine Hminus_ff_longwavelength
!
!  subroutine Hminus_ff_RH(icell, chi)
!  from RH
!  Hminus free-free coefficients in 1d-29 m^5/J
!  see Stilley and Callaway 1970 ApJ 160
!   integer, intent(in) :: icell
!   real(kind=dp), intent(out), dimension(NLTEspec%Nwaves) :: chi
!   integer :: k, index, index2
!   real(kind=dp) :: lambdaFF(NFF), thetaFF(NTHETA)
!   real(kind=dp), dimension(NFF*NTHETA) :: kappaFF_flat
!   real(kind=dp) :: theta(1), pe, kappa(1, NLTEspec%Nwaves)
!   real(kind=dp), dimension(NTHETA,NFF) :: kappaFF
!   data lambdaFF / 0.0, 303.8, 455.6, 506.3, 569.5, 650.9, &
!                   759.4, 911.3, 1013.0, 1139.0, 1302.0,   &
!                   1519.0, 1823.0, 2278.0, 3038.0, 4556.0, &
!                   9113.0 /
!
!   theta = 5040. K / T
!   data thetaFF / 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2,&
!                  1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0 /
!
!   data kappaFF_flat / 0.00d0, 0.00d0, 0.00d0, 0.00d0,&! 0nm
!                  0.00d0, 0.00d0, 0.00d0, 0.00d0,&
!                  0.00d0, 0.00d0, 0.00d0, 0.00d0,&
!                  0.00d0, 0.00d0, 0.00d0, 0.00d0,&
! 3.44d-2, 4.18d-2, 4.91d-2, 5.65d-2, 6.39d-2,&!303.8nm
! 7.13d-2,7.87d-2, 8.62d-2, 9.36d-2, 1.01d-1, &
! 1.08d-1, 1.16d-1, 1.23d-1, 1.30d-1, 1.38d-1, 1.45d-1,&
! 7.80d-2, 9.41d-2, 1.10d-1, 1.25d-1, 1.40d-1,&!455.6nm
! 1.56d-1,1.71d-1, 1.86d-1, 2.01d-1, 2.16d-1, &
! 2.31d-1, 2.45d-1,2.60d-1, 2.75d-1, 2.89d-1, 3.03d-1,&
! 9.59d-2, 1.16d-1, 1.35d-1, 1.53d-1, 1.72d-1,&!506.3 nm
! 1.90d-1,2.08d-1, 2.25d-1, 2.43d-1, 2.61d-1, &
! 2.78d-1, 2.96d-1,3.13d-1, 3.30d-1, 3.47d-1, 3.64d-1,&
! 1.21d-1, 1.45d-1, 1.69d-1, 1.92d-1, 2.14d-1,&!569.5 nm
! 2.36d-1,2.58d-1, 2.80d-1, 3.01d-1, 3.22d-1, &
! 3.43d-1, 3.64d-1,3.85d-1, 4.06d-1, 4.26d-1, 4.46d-1,&
! 1.56d-1, 1.88d-1, 2.18d-1, 2.47d-1, 2.76d-1,&!650.9 nm
! 3.03d-1,3.31d-1, 3.57d-1, 3.84d-1, 4.10d-1, &
! 4.36d-1, 4.62d-1,4.87d-1, 5.12d-1, 5.37d-1, 5.62d-1,&
! 2.10d-1, 2.53d-1, 2.93d-1, 3.32d-1, 3.69d-1,&!759.4 nm
! 4.06d-1, 4.41d-1, 4.75d-1, 5.09d-1, 5.43d-1, &
! 5.76d-1, 6.08d-1, 6.40d-1, 6.72d-1, 7.03d-1, 7.34d-1,&
! 2.98d-1, 3.59d-1, 4.16d-1, 4.70d-1, 5.22d-1,&!911.3 nm
! 5.73d-1,6.21d-1, 6.68d-1, 7.15d-1, 7.60d-1, 8.04d-1,&
! 8.47d-1,8.90d-1, 9.32d-1, 9.73d-1, 1.01d0,&
! 3.65d-1, 4.39d-1, 5.09d-1, 5.75d-1, 6.39d-1,&!1013 nm
! 7.00d-1, 7.58d-1, 8.15d-1, 8.71d-1, 9.25d-1, &
!     9.77d-1, 1.03d0, 1.08d0, 1.13d0, 1.18d0, 1.23d0,&
!     4.58d-1, 5.50d-1, 6.37d-1, 7.21d-1, 8.00d-1,&!1139 nm
!     8.76d-1,9.49d-1, 1.02d0, 1.09d0, 1.15d0, 1.22d0,&
!     1.28d0,1.34d0, 1.40d0, 1.46d0, 1.52d0,&
!     5.92d-1, 7.11d-1, 8.24d-1, 9.31d-1, 1.03d0,&!1302 nm
!     1.13d0, 1.23d0, 1.32d0, 1.40d0, 1.49d0,&
!     1.57d0, 1.65d0, 1.73d0, 1.80d0, 1.88d0, 1.95d0,&
!     7.98d-1, 9.58d-1, 1.11d0, 1.25d0, 1.39d0,&!1519 nm
!     1.52d0, 1.65d0, 1.77d0, 1.89d0, 2.00d0, &
!     2.11d0, 2.21d0, 2.32d0, 2.42d0, 2.51d0, 2.61d0,&
!     1.14d0, 1.36d0, 1.58d0, 1.78d0, 1.98d0,&!1823 nm
!     2.17d0, 2.34d0, 2.52d0, 2.68d0, 2.84d0,&
!     3.00d0, 3.15d0, 3.29d0, 3.43d0, 3.57d0, 3.70d0,&
!     1.77d0, 2.11d0, 2.44d0, 2.75d0, 3.05d0,&!2278 nm
!     3.34d0, 3.62d0, 3.89d0, 4.14d0, 4.39d0,&
!     4.63d0, 4.86d0, 5.08d0, 5.30d0, 5.51d0, &
!     5.71d0,3.10d0, 3.71d0, 4.29d0, 4.84d0, 5.37d0,&!3038 nm
!     5.87d0, 6.36d0, 6.83d0, 7.28d0, 7.72d0, &
!     8.14d0, 8.55d0,8.95d0, 9.33d0, 9.71d0, 1.01d1,&
!     6.92d0, 8.27d0, 9.56d0, 1.08d1, 1.19d1,&!4556 nm
!     1.31d1,1.42d1, 1.52d1, 1.62d1, 1.72d1, 1.82d1,&
!     1.91d1,2.00d1, 2.09d1, 2.17d1, 2.25d1,&
!     2.75d1, 3.29d1, 3.80d1, 4.28d1, 4.75d1,&!9113 nm
!     5.19d1,5.62d1, 6.04d1, 6.45d1, 6.84d1, 7.23d1,&
!     7.60d1,7.97d1, 8.32d1, 8.67d1, 9.01d1 /
!
!   chi = 0d0
!
!   pe = ne(icell) * KBOLTZMANN * T(icell)
!   2-dimensionalize kappaFF_flat for interp2D
!   kappaFF = RESHAPE(kappaFF_flat,(/NTHETA, NFF/))
!   !write(*,*) "Check reshape + interp2D"
!   do index=1,NFF
!   do index2=1,NTHETA
!    kappaFF(index,index2) = &
!       kappaFF_flat(NTHETA*(index-1)+index2)
!   end do
!   end do
!
!   for long wavelengths
!   Can do more efficiently !! that computing for all wavelength
!   as it was all long wavelength and then computing
!   only where it is below for the other wavelengths
!   if ((MAXVAL(NLTEspec%lambda) >= lambdaFF(NFF)) .or. &
!        (MINVAL(NLTEspec%lambda) >= lambdaFF(NFF))) then !if at least one
!    CALL Hminus_ff_longwavelength(icell, chi)
!    !return
!   end if
!
!    theta(1:1) = THETA0 /  T(icell)
!    interpolate kappaFF at theta and lambda using
!    2x 1D cubic Bezier splines
!    kappa = interp2Darr(NTHETA, thetaFF,NFF,lambdaFF,kappaFF,&
!                   1,theta,NLTEspec%Nwaves, NLTEspec%lambda)
!    where(NLTEspec%lambda < lambdaFF(NFF))
!    chi = (Hydrogen%n(1,icell)*1d-29) * pe * kappa(1,:)
!    end where
!
!
!  return
!  end subroutine Hminus_ff_RH
