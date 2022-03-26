! ----------------------------------------------------------------------------------- !
! ----------------------------------------------------------------------------------- !
! This module solves for the radiative transfer equation by ray-tracing for
! multi-level systems using the MALI method
! TO DO: add molecules
! ----------------------------------------------------------------------------------- !
! ----------------------------------------------------------------------------------- !
module atom_transfer

   use atom_type, only  			: AtomType
   use opacity, only             : dealloc_atom_quantities, alloc_atom_quantities, compute_atom_quantities, &
                                 compute_background_continua, opacity_atom_loc, interp_continuum_local, &
                                 nlte_bound_free, Uji_down, chi_up, chi_down, eta_atoms, cross_coupling_terms, &
                                 background_continua_lambda, opacity_atom_zeeman_loc, solve_stokes_mat, prec_pops,&
                                 frac_limit_pops, frac_ne_limit, mean_grad_v, domega_core, mean_length_scale, domega_shock
   use background_opacity, only  : Thomson, HI_rayleigh_part1, HeI_rayleigh_part1
   use Planck, only              : bpnu
   use spectrum_type, only       : dk, dk_max, dk_min, sca_c, chi, eta, chi_c, eta_c, eta_c_nlte, chi_c_nlte, &
                                 eta0_bb, chi0_bb, lambda, Nlambda, lambda_cont, Nlambda_cont, Itot, Icont, Istar_tot, &
                                 Istar_cont, Flux_acc, Ishock, Istar_loc, flux_star, Stokes_Q, Stokes_U, Stokes_V, Flux, &
                                 Fluxc, F_QUV, rho_p, etaQUV_p, chiQUV_p, init_spectrum, &
                                 dealloc_spectrum, Jnu_cont, Jnu, alloc_flux_image, allocate_stokes_quantities, &
                                 dealloc_jnu, reallocate_rays_arrays, write_flux,  &
                                 write_atomic_maps, limage_at_lam0, image_map, &
                                 wavelength_ref, HI_rayleigh_part2, HeI_rayleigh_part2, alloc_wavelengths_raytracing

   use atmos_type, only          : nHtot, icompute_atomRT, lmagnetized, ds, Nactiveatoms, Atoms, calc_ne, Natom, &
                                 ne, T, vr, vphi, v_z, vtheta, wght_per_H, readatmos_ascii, dealloc_atomic_atmos, &
                                 ActiveAtoms, nHmin, hydrogen, helium, lmali_scheme, lhogerheijde_scheme, &
                                 compute_angular_integration_weights, wmu, xmu, xmux, xmuy, v_char, &
                                 angular_quadrature, Taccretion, laccretion_shock, ntotal_atom, helium_is_active, is_inshock
   use healpix_mod, only         : healpix_sphere, healpix_npix, healpix_weight, healpix_ring_mu_and_phi, healpix_listx

   use readatom, only            : read_Atomic_Models, cswitch_enabled, maxval_cswitch_atoms, adjust_cswitch_atoms
   use lte, only                 : set_LTE_populations, nH_minus, ltepops, ltepops_h
   use constant, only            : hc_k, fourpi, NM_TO_M
   use solvene, only             : solve_electron_density_old, solve_electron_density
   use getlambda, only			   : hv
   use voigtfunctions, only	   : Voigt, VoigtHumlicek, dirac_line
   use profiles, only			   : profile, local_profile_v, local_profile_thomson, local_profile_interp, local_profile_dk
   use io_atomic_pops, only	   : write_pops_atom, write_electron, read_electron, write_hydrogen, write_Hminus, &
                                 write_convergence_map_atom, write_convergence_map_electron, prepare_check_pointing
   use io_opacity, only 		   : write_Jnu_cont, write_taur, write_contrib_lambda_ascii, read_Jnu_cont, &
                                 write_collision_matrix_atom, write_collision_matrix_atom_ascii, write_jnu_cont_bin, &
                                 read_jnu_cont_bin, write_radiative_rates_atom, write_rate_matrix_atom, write_cont_opac_ascii, &
                                 write_opacity_emissivity_map, write_dbmatrix_bin
   use math
   !$ use omp_lib
   use molecular_emission, only  : v_proj, vlabs, dv_proj!,gradv
   use input, only               : lkeplerian, linfall, RT_line_method, nb_proc, RT_line_method, &
                                 limb_darkening, mu_limb_darkening
   use parametres, only          : Rmax, Rmin, map_size, zoom, n_cells, lexit_after_nonlte_loop, &
                                 lelectron_scattering, n_rad, nz, n_az, distance, ang_disque, l_sym_ima, etoile, npix_x, npix_y, &
                                 npix_x_save, npix_y_save, lpluto_file, lmodel_ascii, density_file, lsolve_for_ne, &
                                 ltab_wavelength_image, lvacuum_to_air, n_etoiles, lread_jnu_atom, lstop_after_jnu, &
                                 llimb_darkening, dpops_max_error, NRAYS_ATOM_TRANSFER, n_iterate_ne,lforce_lte, loutput_rates, &
                                 ing_norder, ing_nperiod, ing_ndelay, lng_acceleration, mem_alloc_tot, ndelay_iterate_ne, &
                                 llimit_mem, lfix_backgrnd_opac, lsafe_stop, safe_stop_time, checkpoint_period, lcheckpoint, &
                                 istep_start, lno_iterate_ne_mc, laccurate_integ,  healpix_lorder, healpix_lmin, healpix_lmax, &
                                 lvoronoi, lmagnetoaccr, lonly_top, lonly_bottom, l3D, limg, DPOPS_SUB_MAX_ERROR, &
                                 lno_radiative_coupling, lsobolev, lsobolev_only

   use grid, only                : test_exit_grid, cross_cell, pos_em_cellule, move_to_grid
   use Voronoi_grid, only        : Voronoi
   !!use dust_transfer, only		: compute_stars_map
   use dust_ray_tracing, only    : RT_n_incl, RT_n_az, init_directions_ray_tracing,tab_u_RT, tab_v_RT, tab_w_RT, &
                                 tab_RT_az,tab_RT_incl!!, stars_map, kappa
   use stars, only               : intersect_stars!,intersect_spots
   !use wavelengths, only		:
   use mcfost_env, only          : dp, time_begin, time_end, time_tick, time_max
   use constantes, only          : tiny_dp, huge_dp, au_to_m, pc_to_au, deg_to_rad, tiny_real, pi, deux_pi, rad_to_deg, &
                                 masseH, kb, sigma, Lsun, rsun_to_au, au_to_rsun, c_light
   use utils, only               : rotation_3d, cross_product, progress_bar
   use naleat, only              : seed, stream, gtype
   use cylindrical_grid, only    : volume, r_grid, z_grid, phi_grid, cell_map_i, cell_map_j, cell_map_k, area
   use messages, only            : error, warning
   use statequil_atoms, only     : invpop_file, profiles_file, unit_invfile, unit_profiles, calc_bb_rates_hoger, &
                                 calc_bf_rates, calc_rate_matrix, update_populations, update_populations_and_electrons, &
                                 fill_collision_matrix, init_bb_rates_atom, initgamma, initgamma_atom , init_rates_atom, &
                                 store_radiative_rates_mali,calc_rates_draft, store_rate_matrices, psi, calc_rates_mali, &
                                 n_new, ne_new, radiation_free_pops_atom, omega_sor_atom, ldamp_jacobi,&
                                 solve_pops_sobolev

   implicit none
                                                                                                                                 
   !OpenMp and debug
   integer :: omp_chunk_size
   real(kind=dp), allocatable :: convergence_map(:,:,:,:) !say, N_cells, Nlevel, Natom, Nstep
   integer, dimension(:), allocatable :: npix_x_id, npix_y_id, cell_id
   real(kind=dp), dimension(:,:,:), allocatable :: xyz_pos, uvw_pos, chi_loc
   real(kind=dp), dimension(:,:), allocatable :: threeKminusJ, Stest_tot, psi_mean
   !RT procedure
   procedure(integ_ray_line_i), pointer :: integ_ray_line => NULL()
   !Temporary variable for flux calculations
   real(kind=dp), dimension(:,:), allocatable :: QUV
   real(kind=dp), dimension(:), allocatable :: Iacc
   !NLTE
   real(kind=dp) :: dne
   logical :: lfixed_J = .false. !computes and fix J for the non-LTE loop
   ! 	logical :: lNg_acceleration = .true.
   ! 	integer :: iNg_Norder=2, iNg_ndelay=5, iNg_Nperiod=5
   real(kind=dp), allocatable :: ng_cur(:)
   logical, allocatable :: lcell_converged(:)
   real(kind=dp), allocatable :: gpop_old(:,:,:), Tex_old(:,:,:), ngpop(:,:,:)
   real(kind=dp), allocatable :: Gammaij_all(:,:,:,:), Rij_all(:,:,:), Rji_all(:,:,:) !need a flag to output it
   integer :: NmaxLevel, NmaxTr
   !Check-pointing and stopping and timing
   real :: time_iteration, time_nlte

   contains

   subroutine integ_ray_line_i(id,icell_in,x,y,z,u,v,w,iray,labs)
   ! ------------------------------------------------------------------------------- !
   ! Solve equation along ray from icell_in to the edge of the model or 
   ! to a boundary (star, disc etc).
   ! if labs, non-LTE operator is computed.
   ! if lmagnetized, the Zeeman RT equation is solved for images.
   ! if labs, the unpolarized version is used ! (field free approximation).
   ! The source function is constant within each cell.
   ! To Do:
   ! -> remove continuum RT.
   ! ------------------------------------------------------------------------------- !

      integer, intent(in) :: id, icell_in, iray
      real(kind=dp), intent(in) :: u,v,w
      real(kind=dp), intent(in) :: x,y,z
      logical, intent(in) :: labs
      real(kind=dp) :: x0, y0, z0, x1, y1, z1, l, l_contrib, l_void_before, Q, P(4)
      real(kind=dp), dimension(Nlambda) :: Snu, tau, dtau, etas_loc
      real(kind=dp), dimension(Nlambda_cont) :: Snu_c, dtau_c, tau_c, etasc_loc
      integer :: nbr_cell, icell, next_cell, previous_cell, icell_star, i_star, la, icell_prev
      logical :: lcellule_non_vide, lsubtract_avg, lintersect_stars

      x1=x;y1=y;z1=z
      x0=x;y0=y;z0=z
      next_cell = icell_in
      nbr_cell = 0
      icell_prev = icell_in

      tau(:) = 0.0_dp
      tau_c(:) = 0.0_dp

      Itot(:,iray,id) = 0.0_dp
      Icont(:,iray,id) = 0.0_dp
      if (allocated(Stokes_V)) then
         Stokes_V(:,id) = 0.0_dp
         Stokes_Q(:,id) = 0.0_dp 
         Stokes_U(:,id) = 0.0_dp 
      endif
    
      etasc_loc(:) = 0.0_dp
      etas_loc(:) = 0.0_dp

      Istar_loc(:,id) = 0.0_dp
      if (laccretion_shock) Ishock(:,id) = 0.0_dp


      ! Will the ray intersect a star
      call intersect_stars(x,y,z, u,v,w, lintersect_stars, i_star, icell_star)
      ! Boucle infinie sur les cellules (we go over the grid.)
      infinie : do ! Boucle infinie
      ! Indice de la cellule
         icell = next_cell
         x0=x1 ; y0=y1 ; z0=z1

         lcellule_non_vide = (icell <= n_cells)
         ! if (icell <= n_cells) then
         !    lcellule_non_vide=.true.
         ! else
         !    lcellule_non_vide=.false.
         ! endif

         ! Test sortie ! "The ray has reach the end of the grid"
         if (test_exit_grid(icell, x0, y0, z0)) return

         if (lintersect_stars) then !"will interesct"
            if (icell == icell_star) then!"has intersected"
               call local_stellar_radiation(id,iray,tau,tau_c,i_star,icell_prev,x0,y0,z0,u,v,w)
               return
            end if
         endif
         !With the Voronoi grid, somme cells can have a negative index
         !therefore we need to test_exit_grid before using icompute_atom_rt
         if (icell <= n_cells) then
            lcellule_non_vide = (icompute_atomRT(icell) > 0)
            if (icompute_atomRT(icell) < 0) return
         endif

         nbr_cell = nbr_cell + 1

         ! Calcul longeur de vol et profondeur optique dans la cellule
         previous_cell = 0 ! unused, just for Voronoi
         call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell,l, l_contrib, l_void_before)

         !count opacity only if the cell is filled, else go to next cell
         if (lcellule_non_vide) then
            lsubtract_avg = ((nbr_cell == 1).and.labs) !not used yet same as iterate?
            ! opacities in m^-1, l_contrib in au

            !total bound-bound + bound-free + background opacities lte + nlte
            if (llimit_mem) then
               call interp_continuum_local(icell, chi(:,id), eta(:,id))
            else
               chi(:,id) = chi0_bb(:,icell)
               eta(:,id) = eta0_bb(:,icell)
            endif
            !to Do: if llimit_mem, Jnu_cont should be interpolated in interp_continuum_local
            !otherwise, here.
            if (lelectron_scattering) then
               etasc_loc = Jnu_cont(:,icell) * (thomson(icell) + HI_rayleigh_part1(icell) * HI_rayleigh_part2(:))
               if (associated(helium)) then
                  etasc_loc = etasc_loc + Jnu_cont(:,icell) * HeI_rayleigh_part1(icell) * HeI_rayleigh_part2(:)
               endif
               !Or use Jnu, but need _rayleigh_part2 on Nlambda too (at init opac)  to avoid a lots of interpolations.
               !-> check edges of the interpolation !
               !-> pb with the edge of the interpolation routine !
               etas_loc = linear_1D_sorted(Nlambda_cont,lambda_cont,etasc_loc, Nlambda,lambda)
               etas_loc(Nlambda) = etasc_loc(Nlambda_cont)!only if the lambda agrees, at the edge
            endif

            !includes a loop over all bound-bound, passive and active
            if (labs) then!non-LTE
               !.labs. is .true here, so we only test if nbr_cell==1
               call opacity_atom_loc(id,icell,iray,x0,y0,z0,x1,y1,z1,u,v,w,l_void_before,l_contrib,(nbr_cell==1))
            else
               if (lmagnetized) then
                  call opacity_atom_zeeman_loc(id,icell,iray,x0,y0,z0,x1,y1,z1,u,v,w,l_void_before,l_contrib,.false.)
               else
                  call opacity_atom_loc(id,icell,iray,x0,y0,z0,x1,y1,z1,u,v,w,l_void_before,l_contrib,.false.)
               endif
            endif

            dtau(:) = l_contrib * chi(:,id) * AU_to_m !au * m^-1 * au_to_m

            if ((nbr_cell == 1).and.labs) then
               !Lambda operator / chi_dag
               psi(:,iray,id) = ( 1.0_dp - exp( -l_contrib*chi(:,id)* AU_to_m ) ) / chi(:,id)
               !if (allocated(chi_loc)) chi_loc(:,iray,id)  = chi(:,id)
               ds(iray,id) = l_contrib * AU_to_m
            endif

            !add rayleigh scatt to Jnu * emissiviy_scatt
            if (lelectron_scattering) then
               Snu = ( eta(:,id) + etas_loc(:) ) / ( chi(:,id) + tiny_dp )
               Snu_c = eta_c(:,icell) + etasc_loc(:)
            else
               Snu = eta(:,id) / ( chi(:,id) + tiny_dp )
               Snu_c = eta_c(:,icell)
            endif

            if (Nactiveatoms > 0) then
               Snu_c = ( Snu_c + eta_c_nlte(:,icell) ) / ( chi_c(:,icell) + chi_c_nlte(:,icell) + tiny_dp)
               dtau_c(:) = l_contrib * (chi_c(:,icell) + chi_c_nlte(:,icell)) * AU_to_m
            else
               Snu_c = Snu_c / (chi_c(:,icell) + tiny_dp)
               dtau_c(:) = l_contrib * chi_c(:,icell) * AU_to_m
            endif

            if (labs) then
            ! do la=1,Nlambda
               Itot(:,iray,id) = Itot(:,iray,id) + exp(-tau) * (1.0_dp - exp(-dtau)) * Snu
               tau(:) = tau(:) + dtau(:) !for next cell
               if (lno_radiative_coupling) then
                  !ONLY in non-LTE (labs=.true.)
                  !so that idag - psi*eta_atoms dag is -chi_bckgr * Sbckgr/chi
                  !which is expected since for MALI we assume
                  !that the background continua are unchanged during the iteration
                  !TO DO. add stellar radiation
                  return
               endif
            ! enddo
            else
               if (lmagnetized) then
                  do la=1,Nlambda
                     Q = exp(-tau(la)) * (1.0_dp - exp(-dtau(la)))
                     P(1) = Snu(la) * Q
                     call solve_stokes_mat(id,icell,la, Q, P)
                     Itot(la,iray,id) = Itot(la,iray,id) + P(1)
                     Stokes_Q(la,id) = Stokes_Q(la,id) + P(2)
                     Stokes_U(la,id) = Stokes_U(la,id) + P(3)
                     Stokes_V(la,id) = Stokes_V(la,id) + P(4)
                     tau(la) = tau(la) + dtau(la)
                  enddo
               else
                  Itot(:,iray,id) = Itot(:,iray,id) + exp(-tau) * (1.0_dp - exp(-dtau)) * Snu
                  tau(:) = tau(:) + dtau(:) !for next cell
               endif
            endif

            Icont(:,iray,id) = Icont(:,iray,id) + ( exp(-tau_c(:)) - exp(-(tau_c(:) + dtau_c(:))) ) * Snu_c(:)
            tau_c(:) = tau_c(:) + dtau_c(:)

         end if  ! lcellule_non_vide

         icell_prev = icell 
         !duplicate with previous_cell, but this avoid problem with Voronoi grid here

      end do infinie

      return
   end subroutine integ_ray_line_i

   subroutine flux_pixel_line(id,ibin,iaz,n_iter_min,n_iter_max,ipix,jpix,pixelcorner,pixelsize,dx,dy,u,v,w)
   ! -------------------------------------------------------------- !
   ! Computes the flux emerging out of a pixel.
   ! see: mol_transfer.f90/intensite_pixel_mol()
   ! -------------------------------------------------------------- !

      integer, intent(in) :: ipix,jpix,id, n_iter_min, n_iter_max, ibin, iaz
      real(kind=dp), dimension(3), intent(in) :: pixelcorner,dx,dy
      real(kind=dp), intent(in) :: pixelsize,u,v,w
      integer, parameter :: maxSubPixels = 32
      real(kind=dp) :: x0,y0,z0,u0,v0,w0
      real(kind=dp), dimension(Nlambda) :: Iold, I0, I0_star
      real(kind=dp), dimension(Nlambda_cont) :: I0c
      real(kind=dp), dimension(3) :: sdx, sdy
      real(kind=dp):: npix2, diff, normF, R0
      real(kind=dp), parameter :: precision = 1.e-2
      integer :: i, j, subpixels, iray, ri, zj, phik, icell, iter
      logical :: lintersect, labs
      integer :: kr, nr, nb, nat
      type (AtomType), pointer :: atom

      labs = .false.
      ! Ray tracing : on se propage dans l'autre sens
      u0 = -u ; v0 = -v ; w0 = -w

      iray = 1 ! because the direction is fixed and we compute the flux emerging
      ! from a pixel, by computing the Intensity in this pixel
      ! L'obs est en dehors de la grille
      ri = 2*n_rad ; zj=1 ; phik=1

      ! le nbre de subpixel en x est 2^(iter-1)
      subpixels = 1
      iter = 1
      diff = 0.

      infinie : do ! Boucle infinie tant que le pixel n'est pas converge
         npix2 =  real(subpixels)**2
         Iold = I0
         I0 = 0d0
         I0c = 0d0
         I0_star = 0.0_dp
         if (lmagnetized) QUV(:,:) = 0.0_dp !move outside
         if (laccretion_shock) Iacc(:) = 0.0_dp
         ! Vecteurs definissant les sous-pixels
         sdx(:) = dx(:) / real(subpixels,kind=dp)
         sdy(:) = dy(:) / real(subpixels,kind=dp)

       !      !L'obs est en dehors de la grille
       !      ri = 2*n_rad ; zj=1 ; phik=1

         ! Boucle sur les sous-pixels qui calcule l'intensite au centre
         ! de chaque sous pixel
         do i = 1,subpixels
            do j = 1,subpixels
            ! Centre du sous-pixel
               x0 = pixelcorner(1) + (i - 0.5_dp) * sdx(1) + (j-0.5_dp) * sdy(1)
               y0 = pixelcorner(2) + (i - 0.5_dp) * sdx(2) + (j-0.5_dp) * sdy(2)
               z0 = pixelcorner(3) + (i - 0.5_dp) * sdx(3) + (j-0.5_dp) * sdy(3)
               ! On se met au bord de la grille : propagation a l'envers
               call move_to_grid(id, x0,y0,z0,u0,v0,w0, icell,lintersect)
               if (lintersect) then ! On rencontre la grille, on a potentiellement du flux
                  call integ_ray_line(id, icell, x0,y0,z0,u0,v0,w0,iray,labs)

                  I0 = I0 + Itot(:,iray,id)
                  I0c = I0c + Icont(:,iray,id)

                  if (lmagnetized) then
                     QUV(:,3) = QUV(:,3) + Stokes_V(:,id) / npix2
                     QUV(:,2) = QUV(:,2) + Stokes_Q(:,id) / npix2
                     QUV(:,1) = QUV(:,1) + Stokes_U(:,id) / npix2
                  end if

                  if (laccretion_shock) Iacc(:) = Iacc(:) + Ishock(:,id) / npix2

                  if (n_etoiles > 0) I0_star = I0_star + Istar_loc(:,id) / npix2

                !else !Outside the grid, no radiation flux
               endif
            end do !j
         end do !i

         I0 = I0 / npix2
         I0c = I0c / npix2

         if (iter < n_iter_min) then
            ! On itere par defaut
            subpixels = subpixels * 2
         else if (iter >= n_iter_max) then
            ! On arrete pour pas tourner dans le vide
            exit infinie
         else
            ! On fait le test sur a difference
            diff = maxval( abs(I0 - Iold) / (I0 + 1e-300_dp) )
            ! There is no iteration for Q, U, V, assuming that if I is converged, then Q, U, V also.
            ! Can be added and then use diff with I = (sqrt(I**2 + Q**2 + U**2 + V**2))
            if (diff > precision ) then
               ! On est pas converge
               subpixels = subpixels * 2
            else
             !write(*,*) "Pixel converged", ipix, jpix, i, j, iter, diff
               exit infinie
            end if
         end if ! iter
         iter = iter + 1
      end do infinie

      ! Prise en compte de la surface du pixel (en sr)

      ! Flux out of a pixel in W/m2/Hz/pix
      normF = ( pixelsize / (distance*pc_to_AU) )**2

      ! adding to the total flux map.
      !storing by proc is necessary here ?
      Flux(:,ibin,iaz,id) = Flux(:,ibin,iaz,id) + I0(:) * normF
      Fluxc(:,ibin,iaz,id) = Fluxc(:,ibin,iaz,id) + I0c(:) * normF
      if (n_etoiles > 0) then
         Flux_star(:,ibin,iaz,id) = Flux_star(:,ibin,iaz,id) + I0_star(:) * normF
      endif
      if (laccretion_shock) then
         Flux_acc(:,ibin,iaz,id) = Flux_acc(:,ibin,iaz,id) + Iacc(:) * normF
      endif

      if (lmagnetized) then
         F_QUV(:,ibin,iaz,1,id) = F_QUV(:,ibin,iaz,1,id) + normF * QUV(:,1)
         F_QUV(:,ibin,iaz,2,id) = F_QUV(:,ibin,iaz,2,id) + normF * QUV(:,2)
         F_QUV(:,ibin,iaz,3,id) = F_QUV(:,ibin,iaz,3,id) + normF * QUV(:,3)
      end if

      !Proc bug ??? need explicit proc id?
      !Flux map for lines
      !The continuum map is sotred at the location of lambda0, which is not the necessarily the centre
      !of the line in the observer's frame.
      if (RT_line_method==1) then
      !summation over pixels: ipix=1 jpix=1
         do nat=1,Natom
            atom => atoms(nat)%ptr_atom
            do kr=1,atom%Nline

               if (atom%lines(kr)%write_flux_map) then
                  nr = atom%lines(kr)%Nred + dk_max
                  nb = atom%lines(kr)%Nblue + dk_min

                  atom%lines(kr)%map(:,1,1,ibin,iaz) = &
                     atom%lines(kr)%map(:,1,1,ibin,iaz) + I0(nb:nr)*normF

                  atom%lines(kr)%mapc(1,1,ibin,iaz) = &
                     atom%lines(kr)%mapc(1,1,ibin,iaz) + &
                     interp1d_sorted(Nlambda_cont,lambda_cont,I0c, &
                     atom%lines(kr)%lambda0)*normF
                     
                  if (lmagnetized) then
                     atom%lines(kr)%mapx(:,1,1,ibin,iaz,1) = &
                		atom%lines(kr)%mapx(:,ipix,jpix,ibin,iaz,1)  + QUV(nb:nr,1)*normF
                     atom%lines(kr)%mapx(:,1,1,ibin,iaz,2) = &
                		atom%lines(kr)%mapx(:,ipix,jpix,ibin,iaz,2)  + QUV(nb:nr,2)*normF
                     atom%lines(kr)%mapx(:,1,1,ibin,iaz,3) = &
                		atom%lines(kr)%mapx(:,ipix,jpix,ibin,iaz,3)  + QUV(nb:nr,3)*normF
                  endif
               endif

            enddo
            atom => NULL()
         enddo
      else!2D maps
         do nat=1,Natom
            atom => atoms(nat)%ptr_atom
            do kr=1,atom%Nline

               if (atom%lines(kr)%write_flux_map) then
                  nr = atom%lines(kr)%Nred + dk_max
                  nb = atom%lines(kr)%Nblue + dk_min

                  atom%lines(kr)%map(:,ipix,jpix,ibin,iaz) = I0(nb:nr)*normF
                  atom%lines(kr)%mapc(ipix,jpix,ibin,iaz) = &
                  interp1d_sorted(Nlambda_cont,lambda_cont,I0c, atom%lines(kr)%lambda0)*normF
                     
                  if (lmagnetized) then
                     atom%lines(kr)%mapx(:,ipix,jpix,ibin,iaz,1) = QUV(nb:nr,1)*normF
                     atom%lines(kr)%mapx(:,ipix,jpix,ibin,iaz,2) = QUV(nb:nr,2)*normF
                     atom%lines(kr)%mapx(:,ipix,jpix,ibin,iaz,3) = QUV(nb:nr,3)*normF
                  endif
               endif

            enddo
            atom => NULL()
         enddo
       
         if (limage_at_lam0 ) then
            image_map(ipix,jpix,ibin,iaz) = &
               interp1d_sorted(Nlambda,lambda,I0,wavelength_ref)*normF!(pixelsize*zoom/map_size)**2
         endif
      endif


      return
   end subroutine flux_pixel_line

   subroutine emission_line_map(ibin,iaz)
   ! -------------------------------------------------------------- !
   ! Line emission map in a given direction n(ibin,iaz),
   ! using ray-tracing.
   ! if only one pixel it gives the total Flux.
   ! See: emission_line_map in mol_transfer.f90
   ! -------------------------------------------------------------- !
      integer, intent(in) :: ibin, iaz
      real(kind=dp) :: x0,y0,z0,l,u,v,w
      real(kind=dp), dimension(3) :: uvw, x_plan_image, x, y_plan_image, center, dx, dy, Icorner
      real(kind=dp), dimension(3,nb_proc) :: pixelcorner
      real(kind=dp):: taille_pix, nu
      integer :: i,j, id, npix_x_max, n_iter_min, n_iter_max
      integer, parameter :: n_rad_RT = 150, n_phi_RT = 101 !(300,200)!(100, 36)
      real(kind=dp), dimension(n_rad_RT) :: tab_r
      real(kind=dp):: rmin_RT, rmax_RT, fact_r, r, phi, fact_A, cst_phi
      integer :: ri_RT, phi_RT!, lambda
      logical :: lresolved

      write(*,*) "Vector to observer =", real(tab_u_rt(ibin,iaz)),real(tab_v_rt(ibin,iaz)),real(tab_w_rt(ibin))
      write(*,*) "i=", real(tab_RT_incl(ibin)), "az=", real(tab_RT_az(iaz))

      u = tab_u_RT(ibin,iaz) ;  v = tab_v_RT(ibin,iaz) ;  w = tab_w_RT(ibin)
      uvw = (/u,v,w/) !vector position

      ! Definition des vecteurs de base du plan image dans le repere universel
      ! Vecteur x image sans PA : il est dans le plan (x,y) et orthogonal a uvw
      x = (/cos(tab_RT_az(iaz) * deg_to_rad),sin(tab_RT_az(iaz) * deg_to_rad),0._dp/)

      ! Vecteur x image avec PA
      if (abs(ang_disque) > tiny_real) then
         ! Todo : on peut faire plus simple car axe rotation perpendiculaire a x
         x_plan_image = rotation_3d(uvw, ang_disque, x)
      else
         x_plan_image = x
      endif

      ! Vecteur y image avec PA : orthogonal a x_plan_image et uvw
      y_plan_image = -cross_product(x_plan_image, uvw)

      write(*,*) "x-image =           ", real(x_plan_image(:))
      write(*,*) "y-image =           ", real(y_plan_image(:))

      ! position initiale hors modele (du cote de l'observateur)
      ! = centre de l'image
      l = 10.*Rmax  ! on se met loin ! in AU

      x0 = u * l  ;  y0 = v * l  ;  z0 = w * l
      center(1) = x0 ; center(2) = y0 ; center(3) = z0

      ! Coin en bas gauche de l'image
      Icorner(:) = center(:) - 0.5 * map_size * (x_plan_image + y_plan_image)

      if (RT_line_method==1) then !log pixels

         !no sub pixels here
         n_iter_min = 1
         n_iter_max = 1

         dx(:) = 0.0_dp
         dy(:) = 0.0_dp

         i = 1
         j = 1
         lresolved = .false.

         rmin_RT = 0.001_dp * Rmin!max(w*0.9_dp,0.05_dp) * Rmin
         rmax_RT = Rmax * 1.0_dp ! Rmax  * 2.0_dp

         tab_r(1) = rmin_RT
         fact_r = exp( (1.0_dp/(real(n_rad_RT,kind=dp) -1))*log(rmax_RT/rmin_RT) )
         do ri_RT = 2, n_rad_RT
            tab_r(ri_RT) = tab_r(ri_RT-1) * fact_r
         enddo

         fact_A = sqrt(pi * (fact_r - 1.0_dp/fact_r)  / n_phi_RT )


         ! Boucle sur les rayons d'echantillonnage
         !$omp parallel &
         !$omp default(none) &
         !$omp private(ri_RT,id,r,taille_pix,phi_RT,phi,pixelcorner) &
         !$omp shared(tab_r,fact_A,x,x_plan_image,y_plan_image,center,dx,dy,u,v,w,i,j) &
         !$omp shared(n_iter_min,n_iter_max,l_sym_ima,cst_phi,ibin,iaz,fact_r)
         id = 1 ! pour code sequentiel

         if (l_sym_ima) then
            cst_phi = pi  / real(n_phi_RT,kind=dp)
         else
            cst_phi = deux_pi  / real(n_phi_RT,kind=dp)
         endif

         !$omp do schedule(dynamic,1)
         do ri_RT=1, n_rad_RT
            !$ id = omp_get_thread_num() + 1
            r = tab_r(ri_RT)
            taille_pix =  fact_A * r ! racine carree de l'aire du pixel
            do phi_RT=1,n_phi_RT ! de 0 + eps à 2pi - eps (eps = pi/n_phi_RT)
               phi = cst_phi * (real(phi_RT,kind=dp) -0.5_dp)

               pixelcorner(:,id) = center(:) + r * sin(phi) * x_plan_image + r * cos(phi) * y_plan_image
               ! C'est le centre en fait car dx = dy = 0.
               call flux_pixel_line(id,ibin,iaz,n_iter_min,n_iter_max, i,j,pixelcorner(:,id),taille_pix,dx,dy,u,v,w)
            end do !j
         end do !i
         !$omp end do
         !$omp end parallel

         !-> if star_map set dx and dy to
         !!taille_pix = (map_size/zoom)  ! en AU
         !!dx(:) = x_plan_image * taille_pix
         !!dy(:) = y_plan_image * taille_pix


      else !method 2
         ! Vecteurs definissant les pixels (dx,dy) dans le repere universel
         taille_pix = (map_size/zoom) / real(max(npix_x,npix_y),kind=dp) ! en AU
         lresolved = .true.

         dx(:) = x_plan_image * taille_pix
         dy(:) = y_plan_image * taille_pix

         !-> dust_transfer
         !!Icorner(:) = center(:) - ( 0.5 * npix_x * dx(:) +  0.5 * npix_y * dy(:))

         if (l_sym_ima) then
            npix_x_max = npix_x/2 + modulo(npix_x,2)
         else
            npix_x_max = npix_x
         endif

         !$omp parallel &
         !$omp default(none) &
         !$omp private(i,j,id) &
         !$omp shared(Icorner,pixelcorner,dx,dy,u,v,w,taille_pix,npix_x_max,npix_y) &
         !$omp shared(n_iter_min,n_iter_max,ibin,iaz)

         ! loop on pixels
         id = 1 ! pour code sequentiel
         n_iter_min = 1 !1 !3
         n_iter_max = 1 !1 !6
         !$omp do schedule(dynamic,1)
         do i = 1,npix_x_max
            !$ id = omp_get_thread_num() + 1
            do j = 1,npix_y
               pixelcorner(:,id) = Icorner(:) + (i-1) * dx(:) + (j-1) * dy(:)
               call flux_pixel_line(id,ibin,iaz,n_iter_min,n_iter_max,i,j,pixelcorner(:,id),taille_pix,dx,dy,u,v,w)
            end do !j
         end do !i
         !$omp end do
         !$omp end parallel
      end if

      return
   end subroutine emission_line_map


   subroutine calc_mean_grad_v()
      use statequil_atoms, only : Tchoc_average
      !TO DO: iterate to increase the number of rays while dOmega changes ?
      !estimate the mean velocity gradient for each cell
      !by Monte Carlo integration. 
      !For each ray starting in a cell,
      ! the <V> = 1/N sum (abs(v1-v0)) / l_contrib; in s^-1
      ! the solid angle of the "core (or stellar surface)" as seen by a cell
      ! is also computed by counting those rays that intersect the star.
      ! **** Works only for 1 star presently ****
      !
      ! These values can be used in non-LTE line transfer, where basically
      ! the angular integration is done in all direction (so every cell has the 
      ! possibility to hit a star) unlike in the image mode where rays are parralels.
      !
      !
      ! In Sobolev mode, dOmega_c is used to estimate the radiative rates of the continua.
      ! that is Jnu = dOmega_c * Icore (assuming no limb darkening).
      ! the term beta_c * Icore = int(dOmega/4pi beta * Icore) is approximated with 
      ! beta * dOmega_core * Icore
      ! with beta = int(dOmega/4pi (1.0 - exp(-tau_sob))/tau_sob) ~ int(dOmega/4pi (1.0 - exp(-<tau>))/<tau>)),
      ! with <tau> = tau_sob computed with the mean velocity gradient.
#include "sprng_f.h"
      integer :: icell, id, i, previous_cell
      real(kind=dp) :: x0,y0,z0,x1,y1,z1,u,v,w
      real(kind=dp) :: xa,xb,xc,xa1,xb1,xc1,l1,l2,l3
      integer :: next_cell, iray, n_rayons_integ, icell_in, icell1
      integer, parameter :: n_rayons = 100000, lpix_ord = 10
      real :: rand, rand2, rand3
      real(kind=dp) :: W02,SRW02,ARGMT,v0,v1, r0, wei, tmp(nb_proc)
      real(kind=dp) :: l,l_contrib, l_void_before, Tchoc, chi0 = 1d0
      integer :: ibar, n_cells_done, lpix_order_old
      integer :: i_star, icell_star, n_rays_shock(nb_proc)
      logical :: lintersect_stars
      logical, parameter :: lhealpix_mod = .false.
      real(kind=dp), allocatable :: d_to_star(:), Wdi(:), domega_star(:), test_integ(:)

      write(*,*) "computing mean velocity gradient for each cell.."

      ibar = 0
      n_cells_done = 0

      allocate(mean_grad_v(n_cells),mean_length_scale(n_cells))
      !these ones should be (n_cells, n_stars)
      allocate(domega_core(n_cells),d_to_star(n_cells), Wdi(n_cells))
      mean_grad_v = tiny_dp!0.0
      mean_length_scale = 0.0
      domega_core = 0.0
      d_to_star = 0.0
      wdi = 0.0

      if (laccretion_shock) then
         allocate(domega_shock(n_cells))
         domega_shock = 0.0
         Tchoc_average = 0.0
         n_rays_shock = 0
         tmp = 0.0
      !test: function of n_stars in principle
         allocate(domega_star(n_cells)); domega_star = 0.0
      endif

      allocate(test_integ(n_cells)); test_integ = tiny_dp!0.0

      id = 1
      if (lhealpix_mod) then
         write(*,*) " Setting healpix order temporary to", lpix_ord
         write(*,*) " -> input: ", healpix_lorder
         lpix_order_old = healpix_lorder
         healpix_lorder = lpix_ord
         call compute_angular_integration_weights()
         n_rayons_integ = size(xmu)
      else
         stream = 0.0
         do i=1,nb_proc
            stream(i) = init_sprng(gtype, i-1,nb_proc,seed,SPRNG_DEFAULT)
         end do
         n_rayons_integ = n_rayons
      endif
      call progress_bar(0)
      !$omp parallel &
      !$omp default(none) &
      !$omp private(id,icell,iray,rand,rand2,rand3,x0,y0,z0,x1,y1,z1,u,v,w) &
      !$omp private(wei,i_star,icell_star,lintersect_stars,v0,v1,r0)&
      !$omp private(l_contrib,l_void_before,l,W02,SRW02,ARGMT,previous_cell,next_cell) &
      !$omp private(l1,l2,l3,xa,xb,xc,xa1,xb1,xc1,icell_in,Tchoc,icell1) &
      !$omp shared(wmu,xmu,xmux,xmuy,n_rayons_integ,Wdi,d_to_star, dOmega_core,etoile)&
      !$omp shared(phi_grid,r_grid,z_grid,pos_em_cellule,ibar, n_cells_done,stream,n_cells)&
      !$omp shared (mean_grad_v,mean_length_scale,icompute_atomRT,tmp, n_rays_shock)&
      !$omp shared(lvoronoi,Voronoi,laccretion_shock,domega_shock,domega_star, test_integ, chi0)
      !$omp do schedule(static,omp_chunk_size)
      do icell=1, n_cells
         !$ id = omp_get_thread_num() + 1
         if (icompute_atomRT(icell) > 0) then

            !from the centre of the cell is enough
            if (lvoronoi) then
               r0 = sqrt(sum(Voronoi(icell)%xyz(:)**2))
            else
               r0 = sqrt(r_grid(icell)**2+z_grid(icell)**2)
            endif
            d_to_star(icell) = r0 - etoile(1)%r
            Wdi(icell) = 0.5*(1.0 - sqrt(1.0 - (etoile(1)%r/r0)**2))

            do iray=1, n_rayons_integ
               if (lhealpix_mod) then
                  if (lvoronoi) then
                     x0 = Voronoi(icell)%xyz(1)
                     y0 = Voronoi(icell)%xyz(2)
                     z0 = Voronoi(icell)%xyz(3)
                  else
                     x0 = r_grid(icell) * cos(phi_grid(icell))
                     y0 = r_grid(icell) * sin(phi_grid(icell))
                     z0 = z_grid(icell)
                  endif
                  w = xmu(iray)
                  u = xmux(iray)
                  v = xmuy(iray)
                  wei = wmu(iray)
               else
                  rand  = sprng(stream(id))
                  rand2 = sprng(stream(id))
                  rand3 = sprng(stream(id))

                  wei = 1.0/real(n_rayons)

                  call  pos_em_cellule(icell,rand,rand2,rand3,x0,y0,z0)

                  ! Direction de propagation aleatoire
                  rand = sprng(stream(id))
                  W = 2.0_dp * rand - 1.0_dp !nz
                  W02 =  1.0_dp - W*W !1-mu**2 = sin(theta)**2
                  SRW02 = sqrt(W02)
                  rand = sprng(stream(id))
                  ARGMT = PI * (2.0_dp * rand - 1.0_dp)
                  U = SRW02 * cos(ARGMT) !nx = sin(theta)*cos(phi)
                  V = SRW02 * sin(ARGMT) !ny = sin(theta)*sin(phi)
               endif

               call intersect_stars(x0,y0,z0, u,v,w, lintersect_stars, i_star, icell_star)!will intersect

               previous_cell = 0 ! unused, just for Voronoi
               call cross_cell(x0,y0,z0, u,v,w,icell, previous_cell, x1,y1,z1, next_cell,l, l_contrib, l_void_before)
               if (lvoronoi) then
                  if (test_exit_grid(next_cell, x0, y0, z0)) then
                     v1 = 0.0
                  else
                     v1 = v_proj(next_cell,x1,y1,z1,u,v,w)
                  endif
               else
                  v1 = v_proj(icell,x1,y1,z1,u,v,w)
               endif

               if (lintersect_stars) then !"will interesct"
                  dOmega_core(icell) = dOmega_core(icell) + wei
                  icell_in = icell
                  if (laccretion_shock) then !will intersect the shock?
                     !propagate until we reach the stellar surface
                     xa1 = x0; xb1 = y0; xc1 = z0
                     xa = x0; xb = y0; xc = z0
                     inf : do
                        if (next_cell==icell_star) then
                           !in shock ??
                           if (is_inshock(id, iray, i_star, icell_in, xa, xb, xc, Tchoc)) then 
                              dOmega_shock(icell) = dOmega_shock(icell) + wei
                              tmp(id) = tmp(id) + Tchoc
                              n_rays_shock(id) = n_rays_shock(id) + 1
                           else
                              dOmega_star(icell) = domega_star(icell) + wei
                           endif
                           exit inf !because we touch the star
                        endif
                        icell_in = next_cell
                        if (test_exit_grid(icell_in, xa, xb, xc)) exit inf
                        if (icell_in <= n_cells) then
                           if (icompute_atomRT(icell_in) < 0) exit inf
                        endif
                        call cross_cell(xa,xb,xc,u,v,w,icell_in,previous_cell,xa1,xb1,xc1, next_cell,l1,l2,l3)
                        xa = xa1; xb = xb1; xc = xc1
                     enddo inf
                  endif!shock surface
                  !thus, dOmega_shock = f_shock * dOmega_core
                  !dOmega_core  *= (1.0 - f_shock)
               end if !touch star, computes dOmega_core

               v0 = v_proj(icell,x0,y0,z0,u,v,w)
               ! v1 = v_proj(icell1,x1,y1,z1,u,v,w)
               mean_grad_v(icell) = mean_grad_v(icell) + wei * abs(v0-v1)/(l_contrib * AU_to_m)
               mean_length_scale(icell) = mean_length_scale(icell) + wei * l_contrib*AU_to_m
               if (abs(v0-v1) > 0.0) then
                  test_integ(icell) = test_integ(icell) + wei * (1.0 - exp(-chi0*l_contrib * AU_to_m/abs(v0-v1)))/(chi0*l_contrib * AU_to_m/abs(v0-v1))
               endif
            enddo
            ! if (dOmega_core(icell)==0.0_dp) then
            !    write(*,*) Wdi(icell)
            !    call warning("bug solid angle dOmega_core = 0.0")
            !    dOmega_core(icell) = Wdi(icell)
            ! endif
            ! if (laccretion_shock) then
            !    if (dOmega_core(icell)-domega_shock(icell) <= 0.0_dp) then
            !       write(*,*) dOmega_core(icell), domega_shock(icell), domega_star(icell)
            !       call error("bug solid angles")
            !    endif
            ! endif
         endif
         ! Progress bar
         !$omp atomic
         n_cells_done = n_cells_done + 1
         if (real(n_cells_done) > 0.02*ibar*n_cells) then
            call progress_bar(ibar)
            !$omp atomic
            ibar = ibar+1
         endif             
      enddo
      !$omp end do
      !$omp end parallel
      call progress_bar(50)
      if (laccretion_shock) Tchoc_average = sum(tmp) / real(sum(n_rays_shock))

      !just testing
      !how to reconstruct shock surface ??
      ! do icell=1, n_cells
      !    if (icompute_atomRT(icell)) then
      !       write(*,*) 'icell=', icell, ' T=',T(icell), ' nH=',nHtot(icell)
      !       write(*,*) "d = ", d_to_star(icell)/etoile(1)%r," dOmegac=", dOmega_core(icell), " W=",Wdi(icell)
      !       write(*,*) "<gradv> (/s)=", mean_grad_v(icell) * 1d-3, " <l> (Rstar)", mean_length_scale(icell)/(AU_to_m*etoile(1)%r)
      !       if (laccretion_shock) then
      !          write(*,*) "dOmega_shock=", domega_shock(icell),  "dOmegaStar=", domega_star(icell)
      !          ! write(*,*) "f = ", dOmega_shock(icell)*((d_to_star(icell)+etoile(1)%r)/etoile(1)%r)**2, dOmega_core(icell)*((d_to_star(icell)+etoile(1)%r)/etoile(1)%r)**2
      !       endif
      !       write(*,*) "beta=", (1.0-exp(-chi0/mean_grad_v(icell)))/(chi0/mean_grad_v(icell)), test_integ(icell)
      !    endif
      ! enddo
      
      write(*,'("max(<gradv>)="(1ES17.8E3)" s^-1; min(<gradv>)="(1ES17.8E3)" s^-1")') maxval(mean_grad_v), minval(mean_grad_v,icompute_atomRT>0)
      write(*,'("max(dOmegac)="(1ES17.8E3)"; min(dOmegac)="(1ES17.8E3))') maxval(domega_core), minval(domega_core,icompute_atomRT>0)
      if (laccretion_shock) then
         write(*,'("max(dOmega_shock)="(1ES17.8E3)"; min(dOmega_shock)="(1ES17.8E3))') maxval(domega_shock), minval(domega_shock,icompute_atomRT>0)
         write(*,'("max(dOmega*)="(1ES17.8E3)"; min(dOmega*)="(1ES17.8E3))') maxval(domega_star), minval(domega_star,icompute_atomRT>0)
         write(*,*) "<Tshock> = ", Tchoc_average, ' K'
      endif
      write(*,'("max((<beta>-beta)/beta)="(1ES17.8E3)" %; min((<beta>-beta)/beta))="(1ES17.8E3)" %")') &
         100*maxval((((1.0-exp(-chi0/mean_grad_v(:)))/(chi0/mean_grad_v(:))-test_integ)/test_integ)), &
         100*minval((((1.0-exp(-chi0/mean_grad_v(:)))/(chi0/mean_grad_v(:))-test_integ)/test_integ),icompute_atomRT>0)

      if (allocated(test_integ)) deallocate(test_integ)

      deallocate(d_to_star, Wdi)
      if (allocated(domega_star)) deallocate(domega_star)

      if (lhealpix_mod) then
         write(*,*) "Restoring input lorder ..."
         healpix_lorder = lpix_order_old
         write(*,*) " ->", healpix_lorder
      endif

      return
   end subroutine calc_mean_grad_v

   subroutine atom_line_transfer()
   ! --------------------------------------------------------------------------- !
   ! This routine initialises the necessary quantities for atomic line transfer
   ! and calls the appropriate routines for LTE or NLTE transfer.
   ! --------------------------------------------------------------------------- !
      integer :: atomunit = 1, nact
      integer :: icell, m
      integer :: ibin, iaz, kr
      integer :: n_rayons_start
      integer, parameter :: n_rayons_start2 = 1000, maxIter = 11
      integer :: n_rayons_max = n_rayons_start2 * (2**(maxIter-1))
      integer, parameter :: Nrayone = 1
      character(len=20)  :: ne_initial
      logical :: lelectron_read
      type (AtomType), pointer :: atom
      integer :: alloc_status
      real(kind=dp) :: lam0 = 500.0 !default
    
      !init
      lexit_after_nonlte_loop = .false.
      omp_chunk_size = max(nint( 0.01 * n_cells / nb_proc ),1)
      !init at 0
      mem_alloc_tot = 0

      ! -------------------------------INITIALIZE AL-RT ------------------------------------ !
      !only one available yet, I need one unpolarised, faster and more accurate.
      Voigt => VoigtHumlicek
      profile => local_profile_interp
      integ_ray_line => integ_ray_line_i

      if (npix_x_save > 1) then
         RT_line_method = 2 ! creation d'une carte avec pixels carres
         npix_x = npix_x_save ; npix_y = npix_y_save
      else
         RT_line_method = 1 !pixels circulaires
      end if


      ! ------------------------------------------------------------------------------------ !
      ! ------------------------------------------------------------------------------------ !
      !! ----------------------- Read Model ---------------------- !!

      !set .true. in dust_transfer if lmhd_voronoi
      if (lvoronoi) then
         !calling procedure done in dust_transfer.f90
      else
         if (lmodel_ascii) then
            call readAtmos_ascii(density_file)
         else
            call error("Expected model ascii when lmhd_voronoi = .false.!!")
         endif
      endif
      !call empty_cells()
      !if done  after non-LTE, line%a not allocated since local profile is used.
      if (lmagnetized) then
         profile => local_profile_v
      endif

      !! --------------------------------------------------------- !!
      ! ------------------------------------------------------------------------------------ !
      ! ----------------------- READATOM and INITIZALIZE POPS ------------------------------ !
      call read_Atomic_Models(atomunit)

      !not in the model but fits file exists from previous run ?
      call read_electron(lelectron_read)
      if (lelectron_read) then
         ne_initial = "NE_MODEL"
         calc_ne = lsolve_for_ne
      else
         ne_initial = "H_IONISATION"
         if (calc_ne) write(*,*) "Solving for electron density from H+M ionisation"
      endif

      !no electron density in the model nor previous fits file calc_ne == True.
      !if a previous file is found (lelectron_read == True) and lsolve_for_ne, then
      !calc_ne is set to .true. Electron density is re-evaluated using the populations
      !in the fits files (H_Ionisation otherwise).
      if (calc_ne) then !eventually computed with the previous non-LTE pops !
         call Solve_Electron_Density(ne_initial, .true., dne)
         ! 	call Solve_Electron_Density_old(ne_initial)
         call write_Electron
      else
         if (lsolve_for_ne) then
            ne_initial = "NE_MODEL"
            write(*,*) "Forcing calculation of electron density"
            write(*,*) " solution from model!"
            call Solve_Electron_Density(ne_initial, .true., dne)
            call write_Electron
         endif
      endif

      !Populations are written after eventual non-LTE calculations
      call set_LTE_populations 

      if (NactiveAtoms > 0) then
         n_rayons_start = Nrays_atom_transfer

         n_rayons_max = 1

         call init_Spectrum(.true.,n_rayons_max)
         ! call alloc_wavelengths_raytracing(.false.,n_rayons_max)
         if (n_etoiles > 0) call init_stellar_disk
         call alloc_atom_quantities
         call compute_background_continua

         !use the same rays as nlteloop
         if (lelectron_scattering) then
            if (lread_jnu_atom) then
               !If present use previous calculation for initial solution
               call read_jnu_cont_bin
            else
               if (lfixed_J) call iterate_Jnu
               !if not lfixed_J, iterate from scratch (0)
               !otherwise, compute it at LTE and fix it
            endif
         endif

         if (allocated(ds)) deallocate(ds)
         allocate(ds(1, nb_proc), stat=alloc_status)
         if (allocated(vlabs)) deallocate(vlabs)
         allocate(vlabs(1,nb_proc))

         NmaxLevel = 0
         NmaxTr = 0
         do nact=1,Nactiveatoms
            atom => ActiveAtoms(nact)%ptr_atom
            atom%NLTEpops = .true.
            !now we have computed background, lte pops and electron density we can set it to true
            !to use nlte populations in electron density
            allocate(atom%Gamma(atom%Nlevel,atom%Nlevel,nb_proc),stat=alloc_status)
            atom%Gamma(:,:,:) = 0.0_dp
            if (alloc_status > 0) call error("Allocation error atom%Gamma")

            allocate(atom%C(atom%Nlevel,atom%Nlevel,nb_proc),stat=alloc_status)!,n_cells))
            atom%C(:,:,:) = 0.0_dp
            if (alloc_status > 0) then
               write(*,*) nact, atom%ID
               call error("Allocation error atom%C")
            endif

            NmaxLevel = max(NmaxLevel, atom%Nlevel)
            NmaxTr = max(NmaxTr, atom%Ncont + atom%Nline)

            if (atom%initial_solution=="ZERO_RADIATION") then
               !Still H- is at LTE at first.
               write(*,*) "-> Initial solution at SEE with I = 0 for atom ", atom%ID
               !factorize in a new subroutine for all cells ?
               !there is no iteration if I is removed from the equation
               !how, electronic density could be included
               do icell=1,n_cells
                  if (icompute_atomRT(icell) > 0) then
                     call radiation_free_pops_atom(1, icell, atom, .false.)
                  endif
               enddo
               do m=1,atom%Nlevel
                  write(*,"('Level #'(3I1))") m
                  write(*,'("  -- min(n)="(1ES20.7E3)" m^-3; max(n)="(1ES20.7E3)" m^-3")') , &
                     minval(atom%n(m,:),mask=(icompute_atomRT>0)), maxval(atom%n(m,:))
                  write(*,'("  -- min(nstar)="(1ES20.7E3)" m^-3; max(nstar)="(1ES20.7E3)" m^-3")')  &
                     minval(atom%nstar(m,:),mask=(icompute_atomRT>0)), maxval(atom%nstar(m,:))
               enddo
            endif
            mem_alloc_tot = mem_alloc_tot + sizeof(atom%C) + sizeof(atom%Gamma)
            atom => NULL()
         enddo

         allocate(lcell_converged(n_cells),stat=alloc_status)
         if (alloc_status > 0) call error("Allocation error lcell_converged")
         lcell_converged = .false.
         mem_alloc_tot = mem_alloc_tot + sizeof(lcell_converged)

         allocate(Tex_old(NactiveAtoms,NmaxTr,n_cells),stat=alloc_status)
         if (alloc_status > 0) call error("Allocation error Tex_old")
         Tex_old = 0.0_dp
         mem_alloc_tot = mem_alloc_tot + sizeof(Tex_old)

         !remove some arrays in depth to save memory, like vbroad per atom not needed, it is fast to compute locally
         if (loutput_rates) then
            allocate(Rij_all(NactiveAtoms,NmaxTr,n_cells),Rji_all(NactiveAtoms,NmaxTr,n_cells),stat=alloc_status)
            if (alloc_status > 0) call error("Allocation error Rij/Rji _all")
            Rij_all(:,:,:) = 0.0_dp; Rji_all(:,:,:) = 0.0_dp
            allocate(Gammaij_all(NactiveAtoms,Nmaxlevel,Nmaxlevel,n_cells),stat=alloc_status)
            if (alloc_status > 0) call error("Allocation error Gammij_all")
            Gammaij_all(:,:,:,:) = 0.0_dp
            write(*,*) " Size of radiative rates and rate matrix:", (2*sizeof(Rij_all)+sizeof(Gammaij_all))/1024./1024., " MB"
         endif

         write(*,*) " ** Number max of levels among all atoms:", Nmaxlevel
         write(*,*) " ** Number max of transitions among all atoms:", NmaxTr

         if (NactiveAtoms > 1) then
            write(*,*) "   -> Solving for kinetic equations for ", Nactiveatoms, " atoms"
         else
            write(*,*) "   -> Solving for kinetic equations for ", Nactiveatoms, " atom"
         endif
         write(*,*) " Max error : ", dpops_max_error, dpops_sub_max_error
       !!allocate(psi_mean(nlambda, n_cells)); psi_mean = 0.0
       !!allocate(chi_loc(nlambda, n_rayons_max, nb_proc)); chi_loc = 0.0

          write(*,'("->Total memory allocated before NLTEloop:"(1F14.3)" MB")') mem_alloc_tot/1024./1024./1024.

         if (lcheckpoint) call prepare_check_pointing()

         if (lsobolev) then
            call calc_mean_grad_v()
            call solve_pops_sobolev()
            if (.not.lsobolev_only) then
               call NLTEloop_mali(n_rayons_max, n_rayons_start, n_rayons_start2, maxIter)
            endif
         else
            ! ActiveAtoms(1)%ptr_atom%Ntr_line = 0 !remove_lines
            ! ActiveAtoms(1)%ptr_atom%Ntr = ActiveAtoms(1)%ptr_atom%ncont !remove_lines
            ! call NLTEloop_mali(n_rayons_max, n_rayons_start, n_rayons_start2, maxIter)
            ! ActiveAtoms(1)%ptr_atom%Ntr_line = ActiveAtoms(1)%ptr_atom%nline !add_lines
            ! ActiveAtoms(1)%ptr_atom%Ntr = ActiveAtoms(1)%ptr_atom%nline+ActiveAtoms(1)%ptr_atom%ncont !add_lines
            ! ! ActiveAtoms(1)%ptr_atom%Ntr = ActiveAtoms(1)%ptr_atom%Ntr_line !remove_cont
            call NLTEloop_mali(n_rayons_max, n_rayons_start, n_rayons_start2, maxIter)
            ! ! ActiveAtoms(1)%ptr_atom%Ntr = ActiveAtoms(1)%ptr_atom%Ntr_line+ActiveAtoms(1)%ptr_atom%ncont !add_cont
         endif

         if (n_iterate_ne > 0) then
            !Update LTE pops here and nH- if not done during non-LTE loop
            if (lfix_backgrnd_opac) then
               !also update profiles
               call compute_background_continua
            endif
         endif

         !evaluate electron density once SEE is solved
         ! 		if ((.not.lfix_backgrnd_opac) .and. (n_iterate_ne /= 0.0)) then
         if (n_iterate_ne == 0) then
            write(*,*) "Evaluate Electron density from converged populations..."
            ne_initial = "NE_MODEL"
            call solve_electron_density(ne_initial, .true., dne)
            write(*,'("ne(min)="(1ES17.8E3)" m^-3 ;ne(max)="(1ES17.8E3)" m^-3")') minval(ne,mask=(icompute_atomRT>0)), maxval(ne)

            do nact=1, Natom
               if (Atoms(nact)%ptr_atom%ID=="H") then
                  write(*,*) " -> updating LTE pops of hydrogen with non-LTE ne"
                  call LTEpops_H
               else
                  write(*,*) " -> updating LTE pops of ",Atoms(nact)%ptr_atom%ID, " with non-LTE ne"
                  call LTEpops(Atoms(nact)%ptr_atom,.false.)
               endif
            enddo

            do icell=1,n_cells
               if (icompute_atomRT(icell) > 0) then
                  nHmin(icell) = nH_minus(icell)
               endif
            enddo

            call compute_background_continua

            call write_electron
            call write_Hminus
            write(*,*) "...done."
         endif

         deallocate(lcell_converged, Tex_old)
         if (allocated(gpop_old)) deallocate(gpop_old)
         if (allocated(dk)) deallocate(dk)
         if (allocated(ds)) deallocate(ds)
         if (lsobolev) then
            deallocate(mean_grad_v, domega_core, mean_length_scale)
            if (allocated(domega_shock)) deallocate(domega_shock)
         endif

         !dealloc some quantity not needed anymore
         !and write some output
         do nact=1,Natom
            atom => Atoms(nact)%ptr_atom
            if (atom%active) then
               if (allocated(atom%Gamma)) deallocate(atom%Gamma)
               if (allocated(atom%C)) deallocate(atom%C)
               if (loutput_rates) then
             	!To Do: write collision rates instead of matrix (sum over all transitions,
             	! -> informations of individual levels lost !)
                  call write_collision_matrix_atom(atom)
                  call write_radiative_rates_atom(atom, Rij_all(atom%activeindex,1:atom%Ntr,:), &
                     Rji_all(atom%activeindex,1:atom%Ntr,:))
                  call write_rate_matrix_atom(atom, Gammaij_all(atom%activeindex,1:atom%Nlevel,1:atom%Nlevel,:))
               endif
            endif
!           if (loutput_rates) call write_collision_matrix_atom(atom)
            do m=1, atom%Nline
               deallocate(atom%lines(m)%phi_loc)
            enddo
            atom => NULL()
         enddo
         if (loutput_rates) deallocate(Rij_all,Rji_all,Gammaij_all)
         if (lelectron_scattering) then
!         if (lfixed_J) call iterate_jnu
            call write_Jnu_cont_bin
         endif

      endif !end non-LTE

      !for all so after nlte case (debug)
      do m=1,Natom
         call write_pops_atom(Atoms(m)%ptr_atom)
      end do

      if (lexit_after_nonlte_loop) then
         return
       !free all data or because we leave after not needed
      endif

      !call compute_Imu

      if (allocated(vlabs)) deallocate(vlabs)
      allocate(vlabs(Nrayone,nb_proc)); vlabs = 0.0_dp
      ! !now computing image
      !before allocating the grid here, keep only the transitions for which
      !we want a map!
      !at the moment, I use the lcontrib_to_opac!
      if (NActiveAtoms > 0) call dealloc_atom_quantities
      call alloc_wavelengths_raytracing(.true.,Nrayone)
      !TO do. If not npix_x or npix_y > 1; computes the total flux.
      !otherwise, total flux not computed
      !In that case, read the tab_lambda from the file and reset the indexes (do that in init_spectrum)
      if (n_etoiles > 0) call init_stellar_disk
      call alloc_atom_quantities
      call compute_background_continua

      if (lelectron_scattering) then
         call warning("jnu might not be on the same grid now, except if cont is the same!")
         write(*,*) " -> jnu cont must be interpolated locally and lambda_jnu must be stored!"
            !Here Jnu is flat across lines so we only need Jnu_cont to be written
         if (lread_jnu_atom) then
            call read_jnu_cont_bin
               !still starts electron scattering from this value!
               !does not jump at the image calculation yet.
               !this allows to restart a calculation!
         endif
         call iterate_Jnu()
         call write_jnu_cont_bin
         if (lstop_after_jnu) then
            write(*,*) " Jnu calculation done."
            stop
         endif
      endif !electron scatt
              
      if (loutput_rates) then
         call write_opacity_emissivity_map
      endif

      if (lmagnetized) then
         !FOR IMAGE with labs = .false.
         !profile => local_profile_v, this one need line%adamp.
         !re allocate profiles here (to use interpolated profile for non-LTE)
         allocate(QUV(Nlambda,3))
         call allocate_stokes_quantities
      endif
      if (laccretion_shock) allocate(Iacc(nlambda))

      call alloc_flux_image()
      write(*,*) "Computing emission flux map..."
      write(*,'("Total memory allocated for image calculation:"(1ES17.8E3)" GB")') mem_alloc_tot / 1024./1024./1024.

      call init_directions_ray_tracing()
      do ibin=1,RT_n_incl
         do iaz=1,RT_n_az
            call emission_line_map(ibin,iaz)
         end do
      end do
      write(*,*) " ..done"

      if (lmagnetized) then
         deallocate(QUV)
      endif
      if (laccretion_shock) deallocate(Iacc)

      call write_flux(only_flux=.true.)
      call write_atomic_maps

      ! ------------------------------------------------------------------------------------ !
      ! ------------------------------------------------------------------------------------ !
      ! -------------------------------- CLEANING ------------------------------------------ !
      if (allocated(psi_mean)) deallocate(psi_mean, chi_loc)
      if (allocated(QUV)) deallocate(QUV)
      call dealloc_Spectrum !deallocate spectral variables
      call dealloc_atomic_atmos
      nullify(Profile, Voigt, INTEG_RAY_LINE)

      return
   end subroutine atom_line_transfer

  subroutine NLTEloop_mali(n_rayons_max,n_rayons_1,n_rayons_2,maxIter)
    ! ----------------------------------------------------------------------- !
    ! removed all dependency on nrayons since everything is ray by ray built
    ! ----------------------------------------------------------------------- !
#include "sprng_f.h"
    integer, intent(in) :: n_rayons_1, n_rayons_2, maxIter, n_rayons_max
    integer :: etape, etape_start, etape_end, iray, n_rayons, iray_p
    integer :: n_iter, n_iter_loc, id, i, iray_start, alloc_status, la, kr
    integer, dimension(nb_proc) :: max_n_iter_loc
    logical :: lfixed_Rays, lnotfixed_Rays, lconverged, lconverged_loc, lprevious_converged
    real :: rand, rand2, rand3, precision, fac_etape!, precision_sub
    real(kind=dp) :: x0, y0, z0, u0, v0, w0, w02, srw02, argmt, weight
    real(kind=dp) :: diff, norme, dN, dN1, dJ, lambda_max
    real(kind=dp) :: dT, dN2, dN3, dN4, diff_old
    real(kind=dp), allocatable :: dTM(:), dM(:), Tion_ref(:), Tex_ref(:)
    real(kind=dp), allocatable :: Jnew_cont(:,:)
    logical :: labs, update_bckgr_opac
    logical :: l_iterate = .false., l_iterate_ne = .false., update_ne_other_nlte = .false.
    logical :: accelerated, ng_rest, lng_turned_on
    integer :: iorder, i0_rest, n_iter_accel, iacc, iter_sor
    integer :: nact, imax, icell_max, icell_max_2
    integer :: icell, ilevel, imu, iphi, id_ref !for anisotropy
    character(len=20) :: ne_start_sol = "NE_MODEL"
    type (AtomType), pointer :: atom
    integer(kind=8) :: mem_alloc_local = 0
    real(kind=dp) :: diff_cont, conv_speed, conv_acc
    integer :: ibar, n_cells_done
    integer, parameter :: n_iter_counted = 1!iteration time evaluated with n_iter_counted iterations


    write(*,*) " USING MALI METHOD FOR NLTE LOOP"

    !time for individual steps + check the time from the checkpointing time if any
    !and if it is set lconverged = .true. and .lprevious converged == true
    call system_clock(time_begin,count_rate=time_tick,count_max=time_max)


    !-> note: At the moment, hydrogen is always ACTIVE is helium is active and n_iterate_ne > 0!
    !         for simplicity.
    !Hydrogen and Helium updated with SEE if present.
    !For all other non-LTE atoms currently using the old scheme.
    update_ne_other_nlte = (hydrogen%active.and.NactiveAtoms > 1).or.(.not.hydrogen%active)
    !can use helium_is_active global variable, avoiding to test the associated and active.
    if (associated(helium)) then

       update_ne_other_nlte = (helium%active.and.hydrogen%active.and.Nactiveatoms > 2).or.&
            (.not.hydrogen%active.and.helium.active.and.Nactiveatoms > 1).or.&
            (hydrogen%active.and..not.helium%active.and.NactiveAtoms > 1)!.or.&
       !(.not.hydrogen%active.and.helium%active)
       !included in see
    endif

    !!open(unit=unit_invfile, file=trim(invpop_file), status="unknown")
    !!write(unit_invfile,*) n_cells


	if (ldamp_jacobi) then
		iter_sor = 0
		allocate(omega_sor_atom(NactiveAtoms)); omega_sor_atom(:) = 1.0_dp
	endif

    ! 		if (laccurate_integ) then
    ! 			if (iterate_ne) then
    ! 				allocate(convergence_map(n_cells,NmaxLevel,1+NactiveAtoms,2))
    ! 			else
    ! 				allocate(convergence_map(n_cells,NmaxLevel,NactiveAtoms,2))
    ! 			endif
    ! 		else
    ! 			if (iterate_ne) then
    ! 				allocate(convergence_map(n_cells,NmaxLevel,1+NactiveAtoms,1))
    ! 			else
    ! 				allocate(convergence_map(n_cells,NmaxLevel,NactiveAtoms,1))
    ! 			endif
    ! 		endif
    ! 		convergence_map = -1.0_dp

    allocate(dM(Nactiveatoms)); dM=0d0 !keep tracks of dpops for all cells for each atom
    allocate(dTM(Nactiveatoms)); dM=0d0 !keep tracks of Tex for all cells for each atom
    allocate(Tex_ref(Nactiveatoms)); dM=0d0 !keep tracks of max Tex for all cells for each line of each atom
    allocate(Tion_ref(Nactiveatoms)); dM=0d0 !keep tracks of max Tion for all cells for each cont of each atom
    diff_old = 1.0_dp
    dM(:) = 1.0_dp

    mem_alloc_local = mem_alloc_local + sizeof(dM)+sizeof(dTm)+sizeof(Tex_ref)+sizeof(Tion_ref)

    if (lNg_acceleration) then
       n_iter_accel = 0
       i0_rest = 0
       ng_rest = .false.
       iacc = 0
       allocate(ngpop(n_cells * NmaxLevel, iNg_Norder+2, NactiveAtoms), stat=alloc_status)
       if (alloc_status > 0) then
          call error("Cannot allocate Ng table !")
       endif
       mem_alloc_local = mem_alloc_local + sizeof(ngpop)
       !if lng_turned_on is used, iNg_Ndelay is  deprecated and
       !the value of conv_speed is used.
       lng_turned_on = .false.
       iNg_Ndelay = 0
    endif

    if (allocated(stream)) deallocate(stream)
    allocate(stream(nb_proc),stat=alloc_status)
    if (alloc_status > 0) call error("Allocation error stream")

    labs = .true. !to have ds at cell icell = eval_operator
    id = 1
    !In case we restart a calculation in the step 2
    etape_start = istep_start!1
    if (laccurate_integ) then
       etape_end = 2!3, step 3 not implemented yet
    else
       etape_end = 1
       if (istep_start==2) etape_end = 2
    endif

    write(*,*) "---------------------------------------"
    write(*,*) " step start ",etape_start, istep_start
    write(*,*) " step end", etape_end
    write(*,*) "---------------------------------------"

    if (lelectron_scattering.and..not.lfixed_j) then
    !otherwise, Jnu_cont is fixed if lfixed_j and not updated!
       allocate(Jnew_cont(Nlambda_cont, n_cells)); Jnew_cont = 0.0
       mem_alloc_local = mem_alloc_local + sizeof(Jnew_cont)
       write(*,*) " size Jnew_cont:", sizeof(Jnew_cont)/1024./1024./1024.," GB"
    endif

    ! ds is not used for this scheme at  the moment. Psi is used instead
    !since there is no local subit needing recomputing psi
    !! ds(:,:)
    allocate(ne_new(n_cells), stat=alloc_status)
    !ne_new(:) = 0.0_dp
    !-> otherwise if icompute_atomRT(icell) == 2, n_new never updated and is zero!
    ne_new(:) = ne(:)
    if (alloc_status > 0) call error("Allocation error ne_new")
    write(*,*) " size ne_new:", sizeof(ne_new) / 1024./1024.," MB"
    allocate(n_new(NactiveAtoms,Nmaxlevel,n_cells),stat=alloc_status)
    if (alloc_status > 0) call error("Allocation error n_new")
    write(*,*) " size atom%n, n_new:", 2*sizeof(n_new) / 1024./1024.," MB"
    n_new(:,:,:) = 0.0_dp
    allocate(psi(Nlambda, n_rayons_max, nb_proc), stat=alloc_status); psi = 0.0_dp
    write(*,*) " size psi:", sizeof(psi) / 1024./1024.," MB"
    if (alloc_Status > 0) call error("Allocation error psi in nlte loop")
    allocate(eta_atoms(Nlambda,NactiveAtoms,nb_proc),stat=alloc_status)
    if (alloc_Status > 0) call error("Allocation error eta_atoms")
    write(*,*) " size eta_atoms:", sizeof(eta_atoms) / 1024./1024.," MB"
    allocate(Uji_down(Nlambda,Nmaxlevel,NactiveAtoms,nb_proc),stat=alloc_status)
    if (alloc_Status > 0) call error("Allocation error Uji_down")
    write(*,*) " size cross-coupling:", 3 * sizeof(Uji_down) / 1024./1024./1024.," GB"
    allocate(chi_down(Nlambda,Nmaxlevel,NactiveAtoms,nb_proc),stat=alloc_status)
    if (alloc_Status > 0) call error("Allocation error chi_down")
    allocate(chi_up(Nlambda,Nmaxlevel,NactiveAtoms,nb_proc),stat=alloc_status)
    if (alloc_Status > 0) call error("Allocation error chi_up")
    
    if (lNg_acceleration) write(*,*) " size ngpop:", sizeof(ngpop)/1024./1024., " MB"

    mem_alloc_local = mem_alloc_local + sizeof(n_new) + sizeof(psi) + sizeof(eta_atoms) + &
         sizeof(uji_down)+sizeof(chi_down)+sizeof(chi_up) + sizeof(ne_new)

    mem_alloc_tot = mem_alloc_tot + mem_alloc_local
    write(*,'("Total memory allocated in NLTEloop:"(1F14.3)" GB")') mem_alloc_local / 1024./1024./1024.
    write(*,'("Total memory allocated up to now:"(1F14.3)" GB")') mem_alloc_tot / 1024./1024./1024.


    step_loop : do etape=etape_start, etape_end

       if (etape==1) then
          time_iteration = 0

          !Future deprecation with healpix
          if (.not.allocated(xmu)) then
            call compute_angular_integration_weights()
          endif

          lfixed_rays = .true.
          n_rayons = 1 !always
          iray_start = 1

          write(*,*) " Using step 1 with ", size(xmu), " rays"

          lprevious_converged = .false.
          lcell_converged(:) = .false.
          precision = dpops_max_error

       else if (etape==2) then
          time_iteration = 0


          !-> no iteration in MC but after the solution ??
          if (n_iterate_ne > 0) then
             if (lno_iterate_ne_mc) then
                n_iterate_ne = 0
                !in that case, cannot test mod(n_iter, n_iterate_ne) because of division by 0
             endif
          endif

          write(*,*) " Using step 2 with ", n_rayons_1, " rays"
          lfixed_rays = .true.
          n_rayons = n_rayons_1
          iray_start = 1
          lprevious_converged = .false.
          lcell_converged(:) = .false.
          fac_etape = 0.1
          if (etape_start==1) then
             precision = fac_etape * 1e-1!1e-1!1e-3, 1e-2, fac_etape * 1.0 / sqrt(real(n_rayons))
          else
             precision = dpops_max_error
          endif
          write(*,*) " threshold:", precision

          if (lNg_acceleration) then
             deallocate(ngpop)
             if (allocated(ng_cur)) deallocate(ng_cur)
             lNg_acceleration = .false.
          endif

       else if (etape==3) then
          time_iteration = 0
          write(*,*) " Using step 3 with ", n_rayons_max, " nrays max"
          lfixed_rays = .false.
          n_rayons = n_rayons_2
          lprevious_converged = .false.
          lcell_converged(:) = .false.
          precision = 0.1 !dpops_max_error

       else
          call ERROR("etape unkown")
       end if

       lprevious_converged = lforce_lte!avoid useless second iteration.
       lnotfixed_rays = .not.lfixed_rays
       lconverged = .false.
       n_iter = 0
       dne = 0.0_dp
       conv_speed = 0.0
       conv_acc = 0.0

       do while (.not.lconverged)

          n_iter = n_iter + 1
          write(*,*) " -> Iteration #", n_iter, " Step #", etape
          ibar = 0
          n_cells_done = 0
          !!write(unit_invfile,*) "************************************************"
          !!write(unit_invfile,*) "step ", etape, ' iter ', n_iter
          !!write(unit_invfile,*) "************************************************"

          !in step 3 we use the same seed (same sets of random numbers) to add rays to
          !the previously computed.
          if (lfixed_rays) then
             stream = 0.0
             do i=1,nb_proc
                stream(i) = init_sprng(gtype, i-1,nb_proc,seed,SPRNG_DEFAULT)
             end do
          end if

          max_n_iter_loc = 0
          !reset in case of step 3

          !-> instead of mod() frequence of iterations ?
          !( maxval(dM) < min(1e-1,10*precision) )
          !-> add that to prevent oscillations close to convergence ??
          !.and.(.not.lprevious_converged)
          ! 				l_iterate_ne = (n_iterate_ne > 0) .and. ( mod(n_iter,n_iterate_ne)==0 ) .and. (n_iter>ndelay_iterate_ne)
          !need to handle the case n_iterate_ne==0 here for the mod function.
          if( n_iterate_ne > 0 ) then
             l_iterate_ne = ( mod(n_iter,n_iterate_ne)==0 ) .and. (n_iter>ndelay_iterate_ne)
          endif

          call progress_bar(0)
          !$omp parallel &
          !$omp default(none) &
          !$omp private(id,iray,rand,rand2,rand3,x0,y0,z0,u0,v0,w0,w02,srw02, la, dM, dN, dN1,iray_p,imu,iphi)&
          !$omp private(argmt,n_iter_loc,lconverged_loc,diff,norme, icell, nact, atom, l_iterate, weight) &
          !$omp shared(Voronoi,icompute_atomRT, dpops_sub_max_error,lkeplerian,lforce_lte,n_iter, psi_mean, psi, chi_loc) &
          !$omp shared(stream,n_rayons,iray_start, r_grid, z_grid, phi_grid, lcell_converged,loutput_rates, Nlambda_cont, Nlambda, lambda_cont) &
          !$omp shared(n_cells, gpop_old,integ_ray_line, Itot, Icont, Jnu_cont, Jnu, xmu, xmux, xmuy,wmu,etoile,id_ref, xyz_pos,uvw_pos) &
          !$omp shared(Jnew_cont, lfixed_j, lelectron_scattering,chi0_bb, etA0_bb, T,eta_atoms, l_iterate_ne) &
          !$omp shared(nHmin, chi_c, chi_c_nlte, eta_c, eta_c_nlte, ds, Rij_all, Rji_all, Nmaxtr, Gammaij_all, Nmaxlevel) &
          !$omp shared(lvoronoi, lfixed_Rays,lnotfixed_Rays,labs,max_n_iter_loc, etape,pos_em_cellule,Nactiveatoms,lambda, ibar, n_cells_done)
          !$omp do schedule(static,omp_chunk_size) !!dynamic
          do icell=1, n_cells
             !$ id = omp_get_thread_num() + 1
             l_iterate = (icompute_atomRT(icell)>0)

             if (l_iterate) then
                if (lelectron_scattering.and..not.lfixed_j) then
                   Jnew_cont(:,icell) = 0.0
                   !!psi_mean(:,icell) = 0.0
                endif

                call fill_Collision_matrix(id, icell) !computes = C(i,j) before computing rates
                call initGamma(id) !init Gamma to C and init radiative rates
                !psi(:,iray,id) = 0.0_dp !no use full here


                if ( etape == 2) then !ray-by-ray, n_rayons fixed
                   ! Position aleatoire dans la cellule
                   do iray=iray_start, iray_start-1+n_rayons


                      rand  = sprng(stream(id))
                      rand2 = sprng(stream(id))
                      rand3 = sprng(stream(id))

                      call  pos_em_cellule(icell ,rand,rand2,rand3,x0,y0,z0)

                      ! Direction de propagation aleatoire
                      rand = sprng(stream(id))
                      W0 = 2.0_dp * rand - 1.0_dp !nz
                      W02 =  1.0_dp - W0*W0 !1-mu**2 = sin(theta)**2
                      SRW02 = sqrt(W02)
                      rand = sprng(stream(id))
                      ARGMT = PI * (2.0_dp * rand - 1.0_dp)
                      U0 = SRW02 * cos(ARGMT) !nx = sin(theta)*cos(phi)
                      V0 = SRW02 * sin(ARGMT) !ny = sin(theta)*sin(phi)

                      call integ_ray_line(id, icell, x0, y0, z0, u0, v0, w0, 1, labs)

                      if (lelectron_scattering.and..not.lfixed_j) then
                         Jnew_cont(:,icell) = Jnew_cont(:,icell) + Icont(:,1,id) / n_rayons
                      endif

                      !for one ray
                      if (.not.lforce_lte) then
                         call cross_coupling_terms(id, icell, 1)
                         call calc_rates_mali(id, icell, 1, 1.0_dp / real(n_rayons,kind=dp))
                      endif

                      if (loutput_Rates) then
                         !need to take into account the fact that for MALI no quandities are store for all ray so Rij needs to be computed ray by ray
                         call store_radiative_rates_mali(id, icell,(iray==1), 1.0_dp / real(n_rayons,kind=dp), &
                           Nmaxtr, Rij_all(:,:,icell), Rji_all(:,:,icell))
                      endif


                   enddo !iray


                else if (etape==3) then	!accumulate rays, n_rayons not fixed

                   do iray=iray_start, iray_start-1+n_rayons !for the new added rays


                      rand  = sprng(stream(id))
                      rand2 = sprng(stream(id))
                      rand3 = sprng(stream(id))

                      call  pos_em_cellule(icell ,rand,rand2,rand3,x0,y0,z0)

                      ! Direction de propagation aleatoire
                      rand = sprng(stream(id))
                      W0 = 2.0_dp * rand - 1.0_dp !nz
                      W02 =  1.0_dp - W0*W0 !1-mu**2 = sin(theta)**2
                      SRW02 = sqrt(W02)
                      rand = sprng(stream(id))
                      ARGMT = PI * (2.0_dp * rand - 1.0_dp)
                      U0 = SRW02 * cos(ARGMT) !nx = sin(theta)*cos(phi)
                      V0 = SRW02 * sin(ARGMT) !ny = sin(theta)*sin(phi)


                      call integ_ray_line(id, icell, x0, y0, z0, u0, v0, w0, iray, labs)

                   enddo !iray

                   !for all rays accumulated
                   do iray=1, n_rayons !for all
                      if (lelectron_scattering.and..not.lfixed_j) then
                         Jnew_cont(:,icell) = Jnew_cont(:,icell) + Icont(:,iray,id) / n_rayons
                      endif

                      !for one ray
                      if (.not.lforce_lte) then
                         call cross_coupling_terms(id, icell, iray)
                         call calc_rates_mali(id, icell, iray, 1.0_dp / real(n_rayons,kind=dp))
                      endif

                      !might not work cause profile of iray==1 always used
                      if (loutput_Rates) then
                         call store_radiative_rates_mali(id, icell, (iray==1), 1.0_dp / &
                              real(n_rayons,kind=dp), Nmaxtr, Rij_all(:,:,icell), Rji_all(:,:,icell))
                      endif
                   enddo

                elseif (etape==1) then !ray-by-ray, n_rayons fixed

                   if (lvoronoi) then
                   	x0 = Voronoi(icell)%xyz(1)
                   	y0 = Voronoi(icell)%xyz(2)
                   	z0 = Voronoi(icell)%xyz(3)
                   else
                   	x0 = r_grid(icell)*cos(phi_grid(icell))
                   	y0 = r_grid(icell)*sin(phi_grid(icell))
                   	z0 = z_grid(icell)
                   endif

                   do imu=1, size(xmu)

                      w0 = xmu(imu)
                      u0 = xmux(imu)
                      v0 = xmuy(imu)

                      weight = wmu(imu)

                      call integ_ray_line(id, icell, x0, y0, z0, u0, v0, w0, 1, labs)

                      if (lelectron_scattering.and..not.lfixed_j) then
                         Jnew_cont(:,icell) = Jnew_cont(:,icell) + Icont(:,1,id) * weight
                         !!psi_mean(:,icell) = psi_mean(:,icell) + chi_loc(:,1,id) * psi(:,1,id) * weight
                      endif

                      !for one ray
                      if (.not.lforce_lte) then
                         call cross_coupling_terms(id, icell, 1)
                         call calc_rates_mali(id, icell, 1, weight)
                      endif

                      if (loutput_Rates) then
                         !need to take into account the fact that for MALI no quandities are store for all ray so Rij needs to be computed ray by ray
                         call store_radiative_rates_mali(id, icell, (imu==1), weight, Nmaxtr, &
                              Rij_all(:,:,icell), Rji_all(:,:,icell))
                      endif


                   enddo !imu


                end if !etape

                call calc_rate_matrix(id, icell, lforce_lte)
!                 call update_populations(id, icell, diff, .false., n_iter)
                call update_populations_and_electrons(id, icell, diff, .false., n_iter, &
                     (l_iterate_ne.and.icompute_atomRT(icell)==1))!The condition on icompute_atomRT is here because if it is > 0 but /= 1, ne is not iterated!

                n_iter_loc = 0
                if (n_iter_loc > max_n_iter_loc(id)) max_n_iter_loc(id) = n_iter_loc

                if (loutput_Rates) then
                   call store_rate_matrices(id,icell,Nmaxlevel,Gammaij_all(:,:,:,icell))
                endif

             end if !icompute_atomRT
             
             ! Progress bar
             !$omp atomic
             n_cells_done = n_cells_done + 1
             if (real(n_cells_done) > 0.02*ibar*n_cells) then
             	call progress_bar(ibar)
             	!$omp atomic
             	ibar = ibar+1
             endif             
             
          end do !icell
          !$omp end do
          !$omp end parallel
          call progress_bar(50)
          write(*,*) " " !for progress bar

          !Ng acceleration
          !should be para
          accelerated = .false.
!           if ( (lNg_acceleration .and. ((n_iter > iNg_Ndelay).and.(maxval(dM) < 1d-2))).and. &
!                (maxval_cswitch_atoms()==1.0_dp).and.(.not.lprevious_converged) ) then
!           if ( (lNg_acceleration .and. (n_iter > iNg_Ndelay)).and.(maxval_cswitch_atoms()==1.0_dp)&
!           	.and.(.not.lprevious_converged) ) then
          if ( (lNg_acceleration .and. lng_turned_on).and.(maxval_cswitch_atoms()==1.0_dp)&
          	.and.(.not.lprevious_converged) ) then
             iorder = n_iter - iNg_Ndelay
             if (ng_rest) then
                write(*,'(" -> Acceleration relaxes... "(1I2)" /"(1I2))') iorder-i0_rest, iNg_Nperiod
                if (iorder-i0_rest == iNg_Nperiod) ng_rest = .false.
             else
                !Still, all atoms run at the same speed
                i0_rest = iorder
                iacc = iacc + 1
                write(*,'(" -> Accumulate solutions... "(1I2)" /"(1I2))') iacc, iNg_Norder+2
                do nact=1,NactiveAtoms
                   atom => ActiveAtoms(nact)%ptr_atom
                   allocate(ng_cur(n_cells * atom%Nlevel)); ng_cur(:) = 0.0_dp
                   ng_cur = flatten2(atom%Nlevel, n_cells,n_new(nact,1:atom%Nlevel,:))
                   !has to be parallel in the future

                   !for many atoms, increment niter only with the first one, as they go at the same speed.
                   accelerated = ng_accelerate(iacc, ng_cur, n_cells * atom%Nlevel, iNg_Norder, &
                        ngpop(1:atom%Nlevel*n_cells,:,nact), check_negative_pops=.false.)
                        
                    !if check_negative_pops is present :
                    ! if .true., negative pops raise an error.
                    ! if .false. should I cancel the acceleration ?
                    !if not present, there is no checking nor handling.

                   if (accelerated) then
                      !-> only reshape because we only print accelerated iteration for all atoms at once
                      n_new(nact, 1:atom%Nlevel,:) = reform2(atom%Nlevel, n_cells, ng_cur)
                   endif

                   deallocate(ng_cur)
                   atom => NULL()
                enddo
                !for all atoms should be accelerated at the same time
                if (accelerated) then
                   n_iter_accel = n_iter_accel + 1 !True number of accelerated iter
                   write(*,'("     ++> Ng iteration #"(1I4))') n_iter_accel
                   ng_rest = (iNg_Nperiod > 0)!.true.
                   iacc = 0
                endif

             endif
          endif

          if ((mod(n_iter, checkpoint_period)==0).and.(lcheckpoint)) then
             do nact=1, NactiveAtoms
                call write_pops_atom(ActiveAtoms(nact)%ptr_atom,iter=n_iter,step=etape)
             enddo
          endif

          !-> evaluate ne for other non-LTE atoms not included in the non-LTE ionisation scheme ?
          !with fixed non-LTE populations and non-LTE contributions
          update_bckgr_opac = .false.
          if (l_iterate_ne) then

             !update ne from non-LTE ionisation
             !-> no because dne need tu be zeroed for each new iteration of all ne.
             ! 					dne = max(dne, maxval(abs(1.0 - ne(:)/(ne_new(:)+1d-50))))
             dne = maxval(abs(1.0 - ne(:)/(ne_new(:)+1d-50)),mask=icompute_atomRT==1)
             ! 					dne = 0
             ! 					do icell=1,n_cells
             ! 						if (icompute_atomRT(icell)) then
             ! 							dne = max(dne, abs(1.0 - ne(icell)/ne_new(icell)))
             ! 						endif
             ! 					enddo
             write(*,'("OLD ne(min)="(1ES17.8E3)" m^-3 ;ne(max)="(1ES17.8E3)" m^-3")') &
               minval(ne,mask=(icompute_atomRT>0)), maxval(ne)
             write(*,'("NEW ne(min)="(1ES17.8E3)" m^-3 ;ne(max)="(1ES17.8E3)" m^-3")') &
               minval(ne_new,mask=(icompute_atomRT>0)), maxval(ne_new)

             ne(:) = ne_new(:)
             !-> For all elements use the old version
!!! WARNING NOT TESTED YET 05 April 2021 !!!!
             if ( update_ne_other_nlte ) then
                if (helium_is_active .or. hydrogen%active) then
                   call warning("old ne recipe for non-LTE metals not tested yet!")
                endif
                call solve_electron_density(ne_start_sol, .true., dne)
             endif

             do nact=1, Natom
                if (Atoms(nact)%ptr_atom%ID=="H") then
                   write(*,*) " -> updating LTE pops of hydrogen"
                   call LTEpops_H
                   !check pops actually are updated ??
                else
                   write(*,*) " -> updating LTE pops of ",Atoms(nact)%ptr_atom%ID
                   call LTEpops(Atoms(nact)%ptr_atom,.false.)
                endif
             enddo
             write(*,*) ''

             update_bckgr_opac = .true.
          end if

          !Global convergence Tests
          id = 1
          !should be para
          dM(:) = 0.0 !all pops
          diff_cont = 0
          !add a dpops cont ?
          diff = 0.0
          dJ = 0.0
          lambda_max = 0.0
          dT = 0.0
          dTM(:) = 0.0 !all temperature (ion+line)
          Tex_ref(:) = 0.0
          Tion_ref(:) = 0.0
          icell_max = 1
          icell_max_2 = 1
          !for all cells
          dN2 = 0.0 !among all Tex
          dN4 = 0.0 !among all Tion
          cell_loop2 : do icell=1,n_cells

             l_iterate = (icompute_atomRT(icell)>0)

             if (l_iterate) then

                !Local only
                dN = 0.0 !for all levels of all atoms of this cell
                ! 						dN2 = 0.0 !among all Tex
                ! 						dN4 = 0.0 !among all Tion

                ! 						write(*,'(1I4, 1F14.4, 2ES17.8E3)') icell, T(icell), ne(icell), nHtot(icell)
                do nact=1,NactiveAtoms
                   atom => ActiveAtoms(nact)%ptr_atom

                   do ilevel=1,atom%Nlevel
                      ! 								write(*,'(1I2, " fne="(1L1)," fntot="(1L1))') ilevel, n_new(nact,ilevel,icell) >= frac_ne_limit * ne(icell), n_new(nact,ilevel,icell) >= frac_limit_pops * ntotal_atom(icell, atom)
                      ! 								write(*,'("--> n="(1ES17.8E3)," fne="(1ES17.8E3)," fntot="(1ES17.8E3))') n_new(nact,ilevel,icell), frac_ne_limit * ne(icell), frac_limit_pops * ntotal_atom(icell, atom)
                      ! 								write(*,'("--> n/ne="(1ES17.8E3)," n/ntot="(1ES17.8E3))') n_new(nact,ilevel,icell) / ne(icell), n_new(nact,ilevel,icell) / ntotal_atom(icell, atom)
                      ! 								write(*,*) " "
                      ! 								if ( n_new(nact,ilevel,icell) >= frac_ne_limit * ne(icell) ) then
                      if ( n_new(nact,ilevel,icell) >= frac_limit_pops * ntotal_atom(icell, atom) ) then
                         dN1 = abs(1d0-atom%n(ilevel,icell)/n_new(nact,ilevel,icell))
                         ! 									dn1 = abs(-2*atom%n(ilevel,icell) + n_new(nact,ilevel,icell) + gpop_old(nact,ilevel,icell)) /  n_new(nact,ilevel,icell)
                         dN = max(dN1, dN)
                         dM(nact) = max(dM(nact), dN1)
                      endif
                      !convergence_map(icell, ilevel, nact, etape) = dN1
                   end do !over ilevel
                   diff_cont = max(diff_cont, abs(1.0 - atom%n(atom%Nlevel,icell)/(1d-50 + n_new(nact,atom%Nlevel,icell) )))
                   ! 							diff_cont = max(diff_cont, abs(-2*atom%n(atom%Nlevel,icell) + n_new(nact,atom%Nlevel,icell) + gpop_old(nact,atom%Nlevel,icell)) / n_new(nact,atom%Nlevel,icell))

                   !I keep negative Temperatures for info.debug.
                   !hence the /= 0.0. But, some work should be done in update_pops and compute_Tex
                   do kr=1, atom%Nline

                      if (atom%lines(kr)%Tex(icell) /= 0.0_dp) then
                         dN3 = abs(1.0 - Tex_old(nact, kr, icell) /  atom%lines(kr)%Tex(icell) )
                         dN2 = max(dN3,dN2)
                         dTM(nact) = max(dTM(nact), dN3)
                         if (dN3 >= dN2) then
                            Tex_ref(nact) = atom%lines(kr)%Tex(icell)
                            icell_max = icell
                         endif
                      endif

                   enddo

                   do kr=1, atom%Ncont

                      if ( atom%continua(kr)%Tex(icell) /= 0.0_dp) then
                         dN3 = abs(1.0 - Tex_old(nact, kr+atom%Nline, icell) /  atom%continua(kr)%Tex(icell) )
                         dN4 = max(dN3,dN4)
                         dTM(nact) = max(dTM(nact), dN3)
                         if (dN3 >= dN4) then
                            Tion_ref(nact) = atom%continua(kr)%Tex(icell)
                            icell_max_2 = icell
                         endif
                      endif

                   enddo

                   atom => NULL()
                end do !over atoms

                !compare for all atoms and all cells
                diff = max(diff, dN) ! pops
                ! 						diff = max(diff, dN2) ! Texi, only lines


                !do not update if lfixed_J
                if (lelectron_scattering.and..not.lfixed_j) then
                   do la=1, Nlambda_cont
                      dN1 = abs( 1.0_dp - Jnu_cont(la,icell)/Jnew_cont(la,icell) )
                      ! 								if (Jnu(la,icell) > 0.0_dp) then
                      ! 									dN1 = abs( (Jnew(la,icell) - Jnu(la,icell))/Jnu(la,icell) )
                      ! 								endif
                      if (dN1 > dJ) then
                         dJ = dN1
                         lambda_max = lambda_cont(la)
                      endif
                      !updating
                      Jnu_cont(la,icell) = Jnew_cont(la,icell)
                   enddo

                endif

                lcell_converged(icell) = (real(diff) < precision)!.and.(dne < precision)

                !Re init for next iteration if any
                do nact=1, NactiveAtoms
                   atom => ActiveAtoms(nact)%ptr_atom
                   ! 							gpop_old(nact, 1:atom%Nlevel,icell) = atom%n(:,icell)
                   atom%n(:,icell) = n_new(nact,1:atom%Nlevel,icell)
                   do kr=1,atom%Nline
                      Tex_old(nact, kr, icell) = atom%lines(kr)%Tex(icell)
                   enddo
                   do kr=1, atom%Ncont
                      Tex_old(nact, kr+Atom%Nline,icell) = atom%continua(kr)%Tex(icell)
                   enddo
                   !if (.not.lfix_backgrnd_opac) then
                   ! !evalute LTE here ?? if so, need a local version of lte pops.
                   ! !or store the populations nstar in a new array?
                   ! recompute profiles or damping
                   !
                   !endif
                   atom => NULL()
                end do

                !update only if ne has been iterated at this iteration
                !move elsewhere if electron density is iterated with SEE
                if (update_bckgr_opac) then
                   !safe, used only if not lfixbackground
                   nHmin(icell) = nH_minus(icell)
                   ! 							call compute_atom_quantities(icell)
                   !evaluate profiles anyway ?
                   !if I recompute all background continua ?  and damping ? evaluate damping locally ?
                   if (.not.lfix_backgrnd_opac) then!only ne changes
                      !-> this evaluate profiles or damping but also continuum quantities not needed ???
                      !-> do not check ni-njgij < 0 because a non converged state can lead to inversion of populations
                      ! modify it to update only nlte quantities ?
                      call compute_atom_quantities(icell)
                      call background_continua_lambda(icell, Nlambda_cont, lambda_cont, chi_c(:,icell), eta_c(:,icell))
                      !or just re evaluate ne in chi_c like chi_c -ne_old + ne_new
                   endif
                endif

                call NLTE_bound_free(icell)

                !because of opac nlte changed
                if (.not.llimit_mem) then
                   call interp_continuum_local(icell, chi0_bb(:,icell), eta0_bb(:,icell))
                endif
                !end init


             end if !if l_iterate
          end do cell_loop2 !icell
          write(*,'("  ---> dnHII="(1ES17.8E3))') diff_cont  
          !backward derivative
          if (n_iter > 1) then
          	conv_speed = (diff - diff_old) !<0 converging.
          	conv_acc = conv_speed - conv_acc !>0 accelerating
          endif
          !!a more dynamic criterion should be use, that also depends on the atom.
          if (ldamp_jacobi) then
          	!conv_speed is negative if we converge!
          	if (conv_speed <= 0) then
          		if (-conv_speed < 1d-4) then
          			omega_sor_atom(:) = 1.8
          		else
          			omega_sor_atom(:) = 1.0
          		endif
          	else
          		if (conv_speed > 5) then
          			omega_sor_atom(:) = 0.8
          		else
          			omega_sor_atom(:) = 1.0
          		endif
          	endif
          endif
          
          if (lng_acceleration) then
          	!be sure we are converging before extrapolating
          	if ( (n_iter>1).and.(conv_speed <= 0).and.(-conv_speed < 1d-3) ) then
          		if (.not.lng_turned_on) then
          			lng_turned_on = .true.
          			iNg_Ndelay = n_iter
          		endif
          	endif
          endif

          if (maxval(max_n_iter_loc)>0) write(*,'(" -> "(1I10)" sub-iterations")') maxval(max_n_iter_loc)
          write(*,'(" -> icell_max1 #"(2I6)," icell_max2 #"(2I6))') icell_max, icell_max_2
          write(*,*) " ------------------------------------------------ "
          do nact=1,NactiveAtoms
             write(*,'("             Atom "(1A2))') ActiveAtoms(nact)%ptr_atom%ID
             if (accelerated) then
                write(*,'("   >>> dpop="(1ES17.8E3)" (Accelerated)")') dM(nact)
             else
                write(*,'("   >>> dpop="(1ES17.8E3))') dM(nact)
             endif
             write(*,'("   >>>   dT="(1ES17.8E3))') dTM(nact)
             write(*,'("    --->   dT(line)="(1ES17.8E3), " dT(cont)="(1ES17.8E3))') dN2, dN4
             write(*,'("    ->> Te(icell_max2)="(1F14.4)" K", " Tion="(1F14.4)" K")') T(icell_max_2), Tion_ref(nact)
             write(*,'("    ->> Te(icell_max1)="(1F14.4)" K", " Texi="(1F14.4)" K")') T(icell_max), Tex_ref(nact)
             write(*,*) " ------------------------------------------------ "
          enddo
          if (dne /= 0.0_dp) write(*,'("   >>> dne="(1ES17.8E3))') dne
          if (dJ /= 0.0_dp)  write(*,'("   >>> dJ="(1ES14.5E3)" @"(1F14.4)" nm")') dJ, lambda_max !at the end of the loop over n_cells
          write(*,'(" <<->> diff="(1ES17.8E3)," old="(1ES17.8E3))') diff, diff_old !at the end of the loop over n_cells
          write(*,'("   ->> speed="(1ES17.8E3)"; acc="(1ES17.8E3))') conv_speed, conv_acc
          write(*,"('Unconverged cells #'(1I6), ' fraction :'(1F12.3)' %')") &
               size(pack(lcell_converged,mask=(lcell_converged.eqv..false.).and.(icompute_atomRT>0))), &
               100.*real(size(pack(lcell_converged,mask=(lcell_converged.eqv..false.).and.(icompute_atomRT>0)))) / &
               real(size(pack(icompute_atomRT,mask=icompute_atomRT>0)))
          write(*,*) " *************************************************************** "
          diff_old = diff
          conv_acc = conv_speed
               

          ! 				write(*,*) " set lprevious_converged to true for test"
          ! 				lprevious_converged = .true.

          !(real(dne) < precision).and.
          if ((real(diff) < precision).and.(maxval_cswitch_atoms() == 1.0_dp)) then
             if (lprevious_converged) then
                lconverged = .true.
             else
                lprevious_converged = .true.
             endif
          else !continue to iterate even if n_rayons max is reached ?
             lprevious_converged = .false.
             if ((cswitch_enabled).and.(maxval_cswitch_atoms() > 1.0)) then
                call adjust_cswitch_atoms
             endif
             if (.not.lfixed_rays) then !step 3 only
                n_rayons = n_rayons * 2
                write(*,*) ' -- Increasing number of rays :', n_rayons
                if (n_rayons > n_rayons_max) then
                   if (n_iter >= maxIter) then
                      write(*,*) "Warning : not enough rays to converge !!"
                      lconverged = .true.
                   end if
                end if
             else !steps < 3
                if (n_iter > 1000) then
                   write(*,*) "Warning : not enough iterations to converge !!"
                   lconverged = .true.
                end if
             end if
          end if

          !***********************************************************!
          ! ********** timing and checkpointing **********************!

          call system_clock(time_end,count_rate=time_tick,count_max=time_max)
          if (time_end < time_begin) then
             time_nlte=real(time_end + (1.0 * time_max)- time_begin)/real(time_tick)
          else
             time_nlte=real(time_end - time_begin)/real(time_tick)
          endif

          if (n_iter <= n_iter_counted) then
             time_iteration = time_iteration + time_nlte / real(n_iter_counted)
          endif


          if (lsafe_stop) then

             if ((time_nlte + time_iteration >=  safe_stop_time).and.(n_iter >= n_iter_counted)) then
                lconverged = .true.
                lprevious_converged = .true.
                call warning("Time limit would be exceeded, leaving...")
                write(*,*) " time limit:", mod(safe_stop_time/60.,60.) ," min"
                write(*,*) " ~<time> etape:", mod(n_iter * time_iteration/60.,60.), ' <time iter>=', &
                     mod(time_iteration/60.,60.)," min"
                write(*,*) " ~<time> etape (cpu):", mod(n_iter * time_iteration * nb_proc/60.,60.), " min"
                write(*,*) ' time =',mod(time_nlte/60.,60.), " min"
                lexit_after_nonlte_loop = .true.
                !lsafe_stop only would leave the code even if the time is below the walltime
                exit step_loop
             endif

          endif
          !***********************************************************!

       end do !while
       write(*,*) "step: ", etape, "Threshold: ", precision!dpops_max_error
       !real values are possible, not needed and would increase the amount
       !of lign of codes.
       if (n_iter >= n_iter_counted) then
          write(*,*) " ~<time> etape:", mod(n_iter * time_iteration/60.,60.), ' <time iter>=', mod(time_iteration/60.,60.)," min"
          write(*,*) " ~<time> etape (cpu):", mod(n_iter * time_iteration * nb_proc/60.,60.), " min"
       endif

    end do step_loop

    ! -------------------------------- CLEANING ------------------------------------------ !

    if (lNg_acceleration) then
       if (allocated(ngpop)) deallocate(ngpop)
       if (allocated(ng_cur)) deallocate(ng_cur)
    endif
    
    if (ldamp_jacobi) then
    	deallocate(omega_sor_atom)
    endif


    if (allocated(xyz_pos)) then
       ! 			open(unit=20,file="xyz_pos.txt",status="unknown")
       ! 			write(20,*) 1, 1
       ! 			write(20,*) 1627, cell_map_i(1627), cell_map_j(1627), cell_map_k(1627)
       ! 			do iray=1,1
       ! 				write(20,'(*(1E20.7E3))') (xyz_pos(i,iray,1),i=1,3)
       ! 			enddo
       ! 			close(20)
       ! 			open(unit=20,file="uvw_pos.txt",status="unknown")
       ! 			write(20,*) 1, size(xmu), size(xmu)/8
       ! 			do imu=1,size(xmu)
       ! 				write(20,'(*(1E20.7E3))') (uvw_pos(i,imu,1),i=1,3)
       ! 			enddo
       ! 			close(20)
    endif

!     if (allocated(threeKminusJ)) then
!        !only at id_ref until fits file
!        write(*,*) " Writing anisotropy to ascii file..."
! 
!        open(unit=20, file="anis_ascii.txt", status="unknown")
!        write(20,*) n_cells, 1!Nlambda
!        do icell=1, n_cells
!           !do la=1, Nlambda
!           do la=id_ref,id_ref
!              write(20,'(1F12.5,5E20.7E3)') lambda(la), threeKminusJ(la,icell), 0.0, 0.0, 0.0, 0.0
!           enddo
!        enddo
!        close(20)
!        write(*,*) "done"
!        deallocate(threeKminusJ)
!     endif
    if (allocated(psi_mean)) then
       write(*,*) " Writing <Psi> to ascii file..."
       open(unit=20, file="psim_ascii.txt", status="unknown")
       write(20,*) n_cells, Nlambda
       do icell=1, n_cells
          do la=1, Nlambda
             write(20,'(1F12.5,5E20.7E3)') lambda(la), psi_mean(la,icell), 0.0, 0.0, 0.0, 0.0
          enddo
       enddo
       close(20)
       write(*,*) "done"
    endif

    if (allocated(convergence_map)) then
       do nact=1, NactiveAtoms
          call write_convergence_map_atom(ActiveAtoms(nact)%ptr_atom, etape_end, &
               convergence_map(:,1:ActiveAtoms(nact)%ptr_atom%Nlevel, nact, :))
       enddo
       if (l_iterate_ne) call write_convergence_map_electron(etape_end, convergence_map(:,1,NactiveAtoms+1,:))
       deallocate(convergence_map)
    endif

    deallocate(dM, dTM, Tex_ref, Tion_ref)
    if (allocated(Jnew_cont)) deallocate(Jnew_cont)
    deallocate(psi, chi_up, chi_down, Uji_down, eta_atoms, n_new, ne_new)
    deallocate(stream)

    !!close(unit=unit_invfile)

    if (n_iterate_ne > 0) then
       write(*,'("ne(min)="(1ES17.8E3)" m^-3 ;ne(max)="(1ES17.8E3)" m^-3")') minval(ne,mask=icompute_atomRT>0), maxval(ne)
       call write_electron
       call write_Hminus
    endif

    return
  end subroutine NLTEloop_mali


   subroutine init_stellar_disk
      integer :: i_star
      !read stellar radiation here or compute from mcfsot

      write(*,*) " Computing Istar(mu=1) for each star..."
      !move elsewhere if we read a file, but normally should well fit with MCFOST routines
      do i_star=1, n_etoiles
         if (etoile(i_star)%T <= 1e-6) then
            call warning("Setting stellar radiation to 0: T* < 1e-6 K")
            Istar_tot(:,i_star) = 0.0_dp
            Istar_cont(:,i_star) = 0.0_dp
         else
            write(*,"( 'T*('(1I1)') = '(1F14.7)' K' )") i_star, etoile(i_star)%T
            Istar_tot(:,i_star) = Bpnu(etoile(i_star)%T*1d0, lambda)
            Istar_cont(:,i_star) = Bpnu(etoile(i_star)%T*1d0, lambda_cont)
         endif
      enddo
      write(*,*) " ..done"

      return
   end subroutine init_stellar_disk

   subroutine local_stellar_radiation(id,iray,tau,tau_c,i_star,icell_prev,x,y,z,u,v,w)
   ! ---------------------------------------------------------------!
   ! routine to manage the radiation of the stellar boundary
   ! -------------------------------------------------------------- !
   use atmos_type, only : thetai, thetao
      integer, intent(in) :: i_star, icell_prev, id, iray
      real(kind=dp), dimension(:), intent(in) :: tau, tau_c
      real(kind=dp), intent(in) :: u, v, w, x, y, z
      real(kind=dp) :: Tchoc
      real(kind=dp) :: mu, ulimb, LimbDarkening

      if (etoile(i_star)%T <= 1e-6) then !even with spots
         return !no radiation from the star
      endif


      !cos(theta) = dot(r,n)/module(r)/module(n)
      if (llimb_darkening) then
         call ERROR("option for reading limb darkening not implemented")
         mu = abs(x*u + y*v + z*w)/sqrt(x**2+y**2+z**2) !n=(u,v,w) is normalised
         if (real(mu)>1d0) then !to avoid perecision error
            write(*,*) "mu=",mu, x, y, z, u, v, w
            call Error(" mu limb > 1!")
         end if
      else
         LimbDarkening = 1.0_dp
      end if

      Istar_loc(:,id) = Limbdarkening * exp(-tau(:)) * Istar_tot(:,i_star)

      if (is_inshock(id, iray, i_star, icell_prev, x, y, z, Tchoc)) then
         Ishock(:,id) = LimbDarkening * exp(-tau(:)) * Bpnu(Tchoc,lambda)
         Itot(:,iray,id) = Itot(:,iray,id) + Ishock(:,id) + Istar_loc(:,id)
         Icont(:,iray,id) = Icont(:,iray,id) + LimbDarkening * exp(-tau_c(:)) *&
            (Bpnu(Tchoc,lambda_cont) + Istar_cont(:,i_star)) 

         return
      endif

      Itot(:,iray,id) = Itot(:,iray,id) + Istar_loc(:,id)
      Icont(:,iray,id) = Icont(:,iray,id) + LimbDarkening * exp(-tau_c(:)) * &
         Istar_cont(:,i_star)

      return
   end subroutine local_stellar_radiation


   subroutine INTEG_RAY_JNU(id,icell_in,x,y,z,u,v,w,iray,labs, kappa_tot, Snu, Istar, Ic)
    ! ------------------------------------------------------------------------------- !
    ! This routine performs integration of the transfer equation along a ray to
    ! compute coherent Jnu in the continuum
    ! ------------------------------------------------------------------------------- !

    integer, intent(in) :: id, icell_in, iray
    real(kind=dp), intent(in) :: u,v,w
    real(kind=dp), intent(in) :: x,y,z
    real(kind=dp), intent(in), dimension(:,:) :: kappa_tot, Snu
    real(kind=dp), intent(in), dimension(:) :: Istar
    real(kind=dp), intent(out) :: Ic(:,:)
    logical, intent(in) :: labs
    real(kind=dp) :: x0, y0, z0, x1, y1, z1, l, l_contrib, l_void_before
    real(kind=dp), dimension(size(Ic(:,1))) :: LimbD
    real(kind=dp), dimension(size(Ic(:,1))) :: tau_c
    integer :: nbr_cell, icell, next_cell, previous_cell, icell_star, i_star, la, icell_prev
    logical :: lcellule_non_vide, lsubtract_avg, lintersect_stars, eval_operator


    x1=x;y1=y;z1=z
    x0=x;y0=y;z0=z
    next_cell = icell_in
    nbr_cell = 0
    icell_prev = icell_in

    tau_c(:) = 0.0_dp

    Ic(:,id) = 0.0

    eval_operator = .false.
    ! -------------------------------------------------------------- !
    !*** propagation dans la grille ***!
    ! -------------------------------------------------------------- !
    ! Will the ray intersect a star
    call intersect_stars(x,y,z, u,v,w, lintersect_stars, i_star, icell_star)

    ! Boucle infinie sur les cellules
    infinie : do ! Boucle infinie
       ! Indice de la cellule
       icell = next_cell
       x0=x1 ; y0=y1 ; z0=z1

       if (icell <= n_cells) then
          lcellule_non_vide=.true.
       else
          lcellule_non_vide=.false.
       endif

       ! Test sortie ! "The ray has reach the end of the grid"
       if (test_exit_grid(icell, x0, y0, z0)) return

       if (lintersect_stars) then
          if (icell == icell_star) then
             !shock rad is not included here.
             Ic(:,id) =  Ic(:,id) + Istar(:) * exp(-tau_c)
            !  if (is_inshock(id, iray, i_star, icell_prev, x0, y0, z0, Tchoc)) then
            !    Ic(:,id) = Ic(:,id) + Bpnu(Tchoc,lambda_cont) * exp(-tau_c)
            !  endif
             return
          end if
       endif

       if (icell <= n_cells) then
          lcellule_non_vide = (icompute_atomRT(icell) > 0)
          if (icompute_atomRT(icell) < 0) return !-1 if dark
       endif

       nbr_cell = nbr_cell + 1

       ! Calcul longeur de vol et profondeur optique dans la cellule
       previous_cell = 0 ! unused, just for Voronoi
       call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell,l, l_contrib, l_void_before)


       !count opacity only if the cell is filled, else go to next cell
       if (lcellule_non_vide) then
       
          ! opacities in m^-1
          l_contrib = l_contrib * AU_to_m !l_contrib in m

          if ((nbr_cell == 1).and.labs) then
             ds(iray,id) = l_contrib
          endif


          do la=1, Nlambda_cont
          	Ic(la,id) = Ic(la,id) + (exp(-tau_c(la)) - exp(-l_contrib * kappa_tot(la,icell)-tau_c(la))) * Snu(la,icell)
          	tau_c(la) = tau_c(la) + l_contrib * kappa_tot(la,icell)
          enddo

       end if  ! lcellule_non_vide
       icell_prev = icell
    end do infinie
    ! -------------------------------------------------------------- !
    ! -------------------------------------------------------------- !
    return
  end subroutine INTEG_RAY_JNU

  subroutine Iterate_Jnu()
    ! -------------------------------------------------------- !
    ! Compute the mean radiation field at all cells
    ! evaluated on the continuum grid and then interpolated on the
    ! total wavelength grid (and flat across lines).
    !
    ! Future deprecation : Use Monte Carlo methode for the pure
    !   continuum scattering problem.
    ! -------------------------------------------------------- !
#include "sprng_f.h"
    real :: precision
    integer, parameter :: n_iter_max = 300
    integer :: etape, etape_start, etape_end, iray, n_rayons, n_rayons_old
    integer :: n_iter, n_iter_loc, id, i, iray_start, alloc_status
    logical :: lfixed_Rays, lnotfixed_Rays, lconverged, lprevious_converged
    
    real :: rand, rand2, rand3
    real(kind=dp) :: dSource, dN, dj_loc
    real(kind=dp) :: x0, y0, z0, u0, v0, w0, w02, srw02, argmt, diff, norme, dJ, diffs
    real(kind=dp), allocatable :: Jold(:,:), beta(:,:), Istar(:), Ic(:,:,:), J20_cont(:,:)
    real(kind=dp), allocatable :: lambda_star(:,:), Sth(:,:), Sold(:,:), delta_J(:), Snew(:,:) 

    logical :: labs
    integer :: la, icell, imax, icell_max, ibar, n_cells_done
    integer :: imu, iphi, time_iteration, time_nonlte
    integer, parameter :: n_iter_counted = 1!iteration time evaluated with n_iter_counted iterations
    real(kind=dp) :: lambda_max, weight
    
    integer :: n_beta_max
    logical :: lcalc_anisotropy = .false.

    call system_clock(time_begin,count_rate=time_tick,count_max=time_max)

    write(*,'("   --> Solving the continuum scattering (isotropic) problem with "(1I5)" lambda!")') Nlambda_cont
    !Non-LTE loop with starting solution for Jnu
    if (NactiveAtoms > 0) then
       if (lfixed_J) then
          !Jnu kept fixed, same resolution as populations
          precision = dpops_max_error
       else !Starting solution no need to converge a lot
          precision = 1e-1
       endif
    else!No active atoms
       precision = dpops_max_error
    endif

    write(*,*) "   precision in J is ", precision
    write(*,*) " Dynamic scheduling chunk size!", omp_chunk_size
    

    if (allocated(ds)) deallocate(ds)

    !only one star
    allocate(Istar(Nlambda_cont), delta_J(Nlambda_cont), lambda_star(Nlambda_cont, nb_proc))
    Istar = 0.0_dp; delta_J = 0.0; lambda_star = 0.0_dp

    allocate(Jold(Nlambda_cont, n_cells)); Jold = 0.0_dp
    allocate(Sth(Nlambda_cont, n_cells), Snew(Nlambda_cont, n_cells), Sold(Nlambda_cont, n_cells))
    Sth = 0.0_dp; Sold = 0.0_dp; Snew = 0.0_dp
    allocate(beta(Nlambda_cont, n_cells)); beta = 0.0_dp

	if (lcalc_anisotropy) then
		allocate(J20_cont(Nlambda_cont, n_cells)); J20_cont = 0.0_dp
	endif


    if (n_etoiles > 0) then
    	Istar(:) = Istar_cont(:,1)
    	if (n_etoiles > 1) call warning("Multiple stars not handled in iterate_jnu() !!")
    endif
    Jold = Jnu_cont

	!could be parallel
	n_beta_max = 0
    do icell=1, n_cells
       if (icompute_atomRT(icell) > 0) then

		  !to handle case of beta=1 better.
          do la=1,Nlambda_cont
          
          	beta(la,icell) = ( thomson(icell) + HI_rayleigh_part1(icell)*HI_rayleigh_part2(la) ) / chi_c(la,icell)
          	if (associated(helium)) then
          		beta(la,icell) = beta(la,icell) + HeI_rayleigh_part1(icell)*HeI_rayleigh_part2(la) / chi_c(la,icell)
          	endif

			if ( beta(la,icell) < 1.0_dp ) then
          		Sth(la,icell) = eta_c(la,icell) / (chi_c(la,icell)*(1.0_dp-beta(la,icell)))
          	else!beta=1, set Jold to something otherwise ALI does not converge. Use MC methode! 
				n_beta_max = n_beta_max + 1
! 				Sth(la,icell) = Bpnu(T(icell), 2.897771955d6 / T(icell))
! 				beta(la,icell) = 0.9999
          	endif

          	Sold(la,icell) = (1.0_dp-beta(la,icell))*Sth(la,icell) + beta(la,icell) * Jold(la,icell)

          enddo !lambda
		
       endif !icompute_atomRT
    enddo !cells
    write(*,'("beta (max)="(1ES20.7E3)," (min)="(1ES20.7E3))'), &
		maxval(maxval(beta(:,:),dim=2)), minval(minval(beta,dim=2,mask=chi_c>0))
    write(*,'("Kappa_tot (max)="(1ES20.7E3)," (min)="(1ES20.7E3))'), &
		maxval(maxval(chi_c(:,:),dim=2)), minval(minval(chi_c,dim=2,mask=chi_c>0))
    write(*,'("eta (max)="(1ES20.7E3)," (min)="(1ES20.7E3))'), &
		maxval(maxval(eta_c(:,:),dim=2)), minval(minval(eta_c,dim=2,mask=chi_c>0))
			
	if (n_beta_max > 0) then
		write(*,'("WARNING: ~"(1I6)" cells with beta=1 not iterated!")') n_beta_max / Nlambda_cont
		write(*,*) ""
	endif
		
    if (.not.allocated(lcell_converged)) allocate(lcell_converged(n_cells))

    labs = .true.
    id = 1
    etape_start = istep_start!1
    if (laccurate_integ) then
       etape_end = 2!3, step 3 not implemented yet
    else
       etape_end = 1
       if (istep_start==2) etape_end = 2
    endif
    allocate(ds(1, nb_proc))
    ds = 0.0_dp !meters


    step_loop : do etape=etape_start, etape_end
    
       if (etape==1) then
          time_iteration = 0

          call compute_angular_integration_weights()

          lfixed_rays = .true.
          n_rayons = 1
          iray_start = 1

          write(*,*) " Using step 1 with ", size(xmu), " rays"
          write(*,'("Jold (max)="(1ES20.7E3)," (min)="(1ES20.7E3))'), &
			maxval(maxval(Jold(:,:),dim=2)), minval(minval(Jold,dim=2,mask=chi_c>0))
          write(*,'("Sold (max)="(1ES20.7E3)," (min)="(1ES20.7E3))'), &
			maxval(maxval(Sold(:,:),dim=2)), minval(minval(Sold,dim=2,mask=chi_c>0))

          lprevious_converged = .false.
          lcell_converged(:) = .false.
          precision = dpops_max_error
          
          allocate(Ic(Nlambda_cont, 1, nb_proc))
          Ic = 0.0_dp

       else if (etape==2) then
          time_iteration = 0

          write(*,*) " Using step 2 with ", Nrays_atom_transfer, " rays"
          write(*,'("Jold (max)="(1ES20.7E3)," (min)="(1ES20.7E3))'), &
			maxval(maxval(Jold(:,:),dim=2)), minval(minval(Jold,dim=2,mask=chi_c>0))
          write(*,'("Sold (max)="(1ES20.7E3)," (min)="(1ES20.7E3))'), &
			maxval(maxval(Sold(:,:),dim=2)), minval(minval(Sold,dim=2,mask=chi_c>0))

          lfixed_rays = .true.
          n_rayons = Nrays_atom_transfer
          iray_start = 1
          lprevious_converged = .false.
          lcell_converged(:) = .false.
          if (etape_start==1) then
             precision = 1e-1!1e-1!1e-3, 1e-2, fac_etape * 1.0 / sqrt(real(n_rayons))
          else
             precision = dpops_max_error
          endif
          write(*,*) " threshold:", precision
          
          if (allocated(Ic)) deallocate(Ic)
          allocate(Ic(Nlambda_cont, 1, nb_proc))
          Ic = 0.0_dp

       else
          call ERROR("etape unkown")
       end if

       lnotfixed_rays = .not.lfixed_rays
       lconverged = .false.
       n_iter = 0
       
       write(*,*) ""

       do while (.not.lconverged)

          n_iter = n_iter + 1
          ibar = 0
          n_cells_done = 0

          write(*,*) " -> Iteration #", n_iter, " Step #", etape

          if (lfixed_rays) then
          	stream = 0.0
          	do i=1,nb_proc
          		stream(i) = init_sprng(gtype, i-1,nb_proc,seed,SPRNG_DEFAULT)
          	end do
          end if
          
          call progress_bar(0)
          !$omp parallel &
          !$omp default(none) &
          !$omp private(id,iray,rand,rand2,rand3,x0,y0,z0,u0,v0,w0,w02,srw02,iphi,imu) &
          !$omp private(argmt,norme, icell, delta_J, weight) &
          !$omp shared(Voronoi, lambda_cont, lambda_star, Snew, Sold, Sth, Istar, xmu,wmu, xmux, xmuy) &
          !$omp shared(n_iter,gtype, nb_proc,seed,etoile,ibar, n_cells_done) &
          !$omp shared(stream,n_rayons,iray_start, r_grid, z_grid, phi_grid, lcell_converged) &
          !$omp shared(n_cells,ds, Jold, Jnu_cont, beta, chi_c, Ic,icompute_atomRT,J20_cont) &
          !$omp shared(lfixed_Rays,lnotfixed_Rays,labs,etape,pos_em_cellule,lcalc_anisotropy, lvoronoi)
          !$omp do schedule(dynamic,omp_chunk_size)
          do icell=1, n_cells
             !$ id = omp_get_thread_num() + 1

             if (icompute_atomRT(icell)>0) then

             
!              	write(*,*) " cell", icell, " id = ", id
                Jnu_cont(:,icell) = 0.0_dp
                Snew(:,icell) = 0.0_dp
                lambda_star(:,id) = 0.0_dp
                if (lcalc_anisotropy) J20_cont(:,icell) = 0.0_dp


                if (etape==1) then

                   if (lvoronoi) then
                   	x0 = Voronoi(icell)%xyz(1)
                   	y0 = Voronoi(icell)%xyz(2)
                   	z0 = Voronoi(icell)%xyz(3)
                   else
                   	x0 = r_grid(icell)*cos(phi_grid(icell))
                   	y0 = r_grid(icell)*sin(phi_grid(icell))
                   	z0 = z_grid(icell)
                   endif

                   do imu=1, size(xmu)
                      w0 = xmu(imu)
                      u0 = xmux(imu); v0 = xmuy(imu)
                      weight = wmu(imu)

                      call integ_ray_jnu(id, icell, x0, y0, z0, u0, v0, w0, 1, labs, chi_c, Sold, Istar, Ic(:,1,:))

                      !LI
                      Jnu_cont(:,icell) = Jnu_cont(:,icell) + Ic(:,1,id) * weight

                      !ALI
                      lambda_star(:,id) = lambda_star(:,id) + (1d0 - exp(-ds(1,id)*chi_c(:,icell))) * weight

                   enddo !imu
                   
                elseif (etape==2) then
                
                   weight = 1.0 / real(n_rayons)
                   do iray=iray_start, iray_start-1+n_rayons


                      rand  = sprng(stream(id))
                      rand2 = sprng(stream(id))
                      rand3 = sprng(stream(id))

                      call  pos_em_cellule(icell,rand,rand2,rand3,x0,y0,z0)

                      ! Direction de propagation aleatoire
                      rand = sprng(stream(id))
                      W0 = 2.0_dp * rand - 1.0_dp !nz
                      W02 =  1.0_dp - W0*W0 !1-mu**2 = sin(theta)**2
                      SRW02 = sqrt(W02)
                      rand = sprng(stream(id))
                      ARGMT = PI * (2.0_dp * rand - 1.0_dp)
                      U0 = SRW02 * cos(ARGMT) !nx = sin(theta)*cos(phi)
                      V0 = SRW02 * sin(ARGMT) !ny = sin(theta)*sin(phi)


                      call integ_ray_jnu(id, icell, x0, y0, z0, u0, v0, w0, 1, labs, chi_c, Sold, Istar, Ic(:,1,:))

                      !LI
                      Jnu_cont(:,icell) = Jnu_cont(:,icell) + Ic(:,1,id) * weight

                      !ALI
                      lambda_star(:,id) = lambda_star(:,id) + (1d0 - exp(-ds(1,id)*chi_c(:,icell))) * weight

                   enddo !iray

                else
                   call error("step unknown!")
                end if !etape

                !ALI
                delta_J(:) = Jnu_cont(:,icell) - Lambda_star(:,id) * Sold(:,icell)
                Snew(:,icell) = (beta(:,icell)*delta_J(:) + (1.0_dp-beta(:,icell))*Sth(:,icell))/(1.0_dp-beta(:,icell)*Lambda_star(:,id))
                !LI
                !Snew(:,icell) = Sth(:,icell) * (1.0_dp - beta(:,icell)) + Jnu_cont(:,icell) * beta(:,icell)

				if (lcalc_anisotropy) J20_cont(:,icell) = J20_cont(:,icell) + (3.0 * (u0*x0+v0*y0+w0*z0)**2/(x0**2+y0**2+z0**2) - 1.0) &
                           * Ic(:,1,id) * weight
             endif !icompute_AtomRT

             ! Progress bar
             !$omp atomic
             n_cells_done = n_cells_done + 1
             if (real(n_cells_done) > 0.02*ibar*n_cells) then
             	call progress_bar(ibar)
            	!$omp atomic
             	ibar = ibar+1
             endif

          end do !icell
          !$omp end do
          !$omp end parallel
          call progress_bar(50)

          !convergence!	
		  icell_max	= 1
		  imax = 1
          diff = 0d0
          dSource = 0.0_dp
          !$omp parallel &
          !$omp default(none) &
          !$omp private(id,icell, la, dJ, dN, dj_loc) &
          !$omp shared(icompute_atomRT, beta, Sth, eta_c, chi_c, T, ne, Jold, Jnu_cont, Sold, Snew, lcell_converged) &
          !$omp shared(Nlambda_cont, lambda_cont, n_cells, dSource, diff, icell_max, precision, imax)
          !$omp do schedule(dynamic, omp_chunk_size)
          cell_loop2 : do icell=1, n_cells
             !$ id = omp_get_thread_num() + 1
             if (icompute_atomRT(icell)>0) then
                dJ = 0.0_dp!over lambda
                dN = 0.0_dp!over lambda
                do la=1, Nlambda_cont
! 		    		if (Jnu_cont(la,icell) > 0.0) then
! 					 	dj_loc = abs( 1.0_dp -Jold(la,icell)/max(Jnu_cont(la,icell),tiny_dp) )
					 	dj_loc = abs( Jnu_cont(la,icell) - Jold(la,icell) )/ max(Jnu_cont(la,icell),tiny_dp)
! 					 	dj_loc = abs( Jnu_cont(la,icell) - Jold(la,icell) )/ max(Jold(la,icell),tiny_dp)
					 	if (dj_loc > dJ) then
					 		dJ = dj_loc
					 		imax = la
					 	endif
! 					endif
!                     	dN = max( dN, abs( 1.0_dp - Sold(la,icell)/(max(Snew(la,icell),tiny_dp)) ) )
                    	dN = max( dN, abs( Snew(la,icell) - Sold(la,icell) )/ max(Snew(la,icell),tiny_dp) )
!                     endif
         	 	    Sold(la,icell) = Snew(la,icell)
          		    Jold(la,icell) = Jnu_cont(la,icell)
                enddo
                !over cells
                dSource = max(dSource, dN)
				!over cells
                if (dJ > diff) then
                   diff = dJ
                   icell_max = icell
                endif
                lcell_converged(icell) = (real(dJ) < precision)
             end if
          end do cell_loop2 !icell
          !$omp end do
          !$omp end parallel
          
! if (is_nan_infinity(dSource)>0) then
! 	write(*,*) "dSource is nan!"
! 	write(*,*) maxval(Sold), minval(Sold)
! 	write(*,*) maxval(Snew),minval(Snew)
! endif
! if (is_nan_infinity(diff)>0) then
! 	write(*,*) "dJ is nan!"
! 	write(*,*) maxval(Jold), minval(Jold)
! 	write(*,*) maxval(Jnu_cont),minval(Jnu_cont)
! endif

          write(*,'(" >>> dS = "(1ES14.5E3)," T(icell_max)="(1F14.5)" K", " ne(icell_max)="(1ES14.5E2))') &
               dSource, T(icell_max), ne(icell_max)
          write(*,'("  -- beta ="(1ES14.5E3))') beta(imax,icell_max)
          write(*,'(" >>> icell_max "(1I7)," lambda="(1F14.7) " nm"," dJ="(1ES14.5E3))') icell_max, lambda(imax), diff

          write(*,'(" @icell_max : Jmax="(1ES14.5E3)," Jmin="(1ES14.5E3) )') &
               maxval(Jnu_cont(:,icell_max)), minval(Jnu_cont(:,icell_max),mask=Jnu_cont(:,icell_max)>0)
          write(*,'(" global     : Jmax="(1ES14.5E3)," Jmin="(1ES14.5E3) )') &
               maxval(Jnu_cont(:,:)), minval(Jnu_cont(:,:),mask=Jnu_cont>0)

          write(*,"('# unconverged cells :'(1I7), '('(1F12.3)' %)')") &
               size(pack(lcell_converged,mask=(lcell_converged.eqv..false.).and.(icompute_atomRT>0))), &
               100.*real(size(pack(lcell_converged,mask=(lcell_converged.eqv..false.).and.(icompute_atomRT>0)))) / &
               real(size(pack(icompute_atomRT,mask=icompute_atomRT>0)))
          write(*,*) ""
          
          if (diff < precision) then
             if (lprevious_converged) then
                lconverged = .true.
             else
                lprevious_converged = .true.
             endif
          else
             lprevious_converged = .false.
             if (lfixed_rays) then
                if (n_iter > n_iter_max) then
                   write(*,*) "Warning Iterate_Jnu : not enough iterations to converge !!"
                   lconverged = .true.
                endif
             endif
          end if
          
          !***********************************************************!
          ! ********** timing and checkpointing **********************!

          call system_clock(time_end,count_rate=time_tick,count_max=time_max)
          if (time_end < time_begin) then
             time_nlte=real(time_end + (1.0 * time_max)- time_begin)/real(time_tick)
          else
             time_nlte=real(time_end - time_begin)/real(time_tick)
          endif

          if (n_iter <= n_iter_counted) then
             time_iteration = time_iteration + time_nlte  / real( n_iter_counted)
          endif


          if (lsafe_stop) then

             if ((time_nlte + time_iteration >=  safe_stop_time).and.(n_iter >= n_iter_counted)) then
                lconverged = .true.
                lprevious_converged = .true.
                call warning("Time limit would be exceeded, leaving...")
                write(*,*) " time limit:", mod(safe_stop_time/60.,60.) ," min"
                write(*,*) " ~<time> etape:", mod(n_iter * time_iteration/60.,60.), ' <time iter>=', &
                     mod(time_iteration/60.,60.)," min"
                write(*,*) " ~<time> etape (cpu):", mod(n_iter * time_iteration * nb_proc/60.,60.), " min"
                write(*,*) ' time =',mod(time_nlte/60.,60.), " min"
                lexit_after_nonlte_loop = .true.
                !lsafe_stop only would leave the code even if the time is below the walltime
                exit step_loop
             endif

          endif

       end do !while
       write(*,*) etape, "Threshold =", precision
       
       if (n_iter >= n_iter_counted) then
          write(*,*) " ~<time> etape:", mod(n_iter * time_iteration/60.,60.), ' <time iter>=', mod(time_iteration/60.,60.)," min"
          write(*,*) " ~<time> etape (cpu):", mod(n_iter * time_iteration * nb_proc/60.,60.), " min"
       endif
       
    end do step_loop!over etapes


    !For non-LTE loop
    ! 	if (.not.lstop_after_jnu) then
    !interpolated locally 
!     Jnu(:,:) = 0.0_dp
!     do icell=1, n_cells
!        if (icompute_atomRT(icell)>0) then
!           call bezier2_interp(Nlambda_cont, lambda_cont, Jnu_cont(:,icell), Nlambda, lambda, Jnu(:,icell))
!        endif
!     enddo
    ! 	endif


! 	
!     	open(unit=20, file="Jnu_no_interp.s", status="unknown")
!     	write(20,*) n_cells, Nlambda_cont
!    		do icell=1, n_cells
!        		do la=1, Nlambda_cont !if you change the format, check read_Jnu_ascii()
!           		if (lambda_cont(la) < 1d5) then
!              		write(20,'(1F12.5,5E20.7E3)') &
!                   	lambda_cont(la), Jnu_cont(la,icell), Sth(la,icell), beta(la,icell), chi_c(la,icell), Sold(la,icell)
!           		else
!              		write(20,'(1F15.5,5E20.7E3)') &
!                   	lambda_cont(la), Jnu_cont(la,icell), Sth(la,icell), beta(la,icell), chi_c(la,icell), Sold(la,icell)
!          		endif
!        		enddo
!     	enddo
!     	close(20)

	if (lcalc_anisotropy) then
	
		call write_dbmatrix_bin("j20c_bin",J20_cont)
		deallocate(J20_cont)
		
    endif


    if (allocated(xmu)) deallocate(xmu,wmu,xmux,xmuy) !in case we call nlte_loop after
    deallocate(ds, lcell_converged)
    deallocate(Jold, Sth, beta, Istar, Ic, Sold, lambda_star, Snew, delta_J)

    ! ------------------------------------------------------------------------------------ !
    return
   end subroutine Iterate_Jnu

   subroutine compute_Imu()
   !
   ! Solve for the radiation intensity at specific location parralel
   ! to the z axis.
   ! To Do:
   ! add Polarized "intensity"
   use utils, only: Gauss_Legendre_quadrature, span
   use constantes, only : Au_to_Rsun

      integer, parameter :: Nmu = 500
      real(kind=dp) :: u, v, w, uvw(3), x(3), y(3)
      integer :: id, icell0, icell, i, j, iray, alloc_status
      real(kind=dp), dimension(:), allocatable :: weight_mu, cos_theta, p, q
      integer, parameter :: maxSubPixels = 32
      real(kind=dp) :: x0,y0,z0,u0,v0,w0, r0, r1, rr, phi
      real(kind=dp), dimension(:,:,:), allocatable :: Imu, Imuc
      real(kind=dp), dimension(:,:,:), allocatable :: IQ,IU,IV
      real(kind=dp):: normF
      logical :: lintersect, labs

      allocate(weight_mu(Nmu), cos_theta(Nmu), p(Nmu), q(Nmu), stat=alloc_status)
      if (alloc_status > 0) call error(" Allocation error cos_theta(Nmu)")
      allocate(Imu(Nlambda,Nmu,1), Imuc(Nlambda_cont,Nmu,1), stat=alloc_status)
      if (alloc_status > 0) call error(" Allocation error Imu, Imuc")
      if (lmagnetized) then
         allocate(IQ(Nlambda,Nmu,1), IU(Nlambda,Nmu,1),IV(Nlambda,Nmu,1), stat=alloc_status)
         if (alloc_status > 0) call error(" Allocation error Q,U,V")
      endif


      Imu(:,:,:) = 0.0_dp
      Imuc(:,:,:) = 0.0_dp
      labs = .false.
      id = 1
      iray = 1
      phi = pi

      !look parallel to z
      u = 0.0_dp
      v = 0.0_dp!-1.745d-22!
      w = 1.0_dp

      uvw = (/u,v,w/) !vector position
      x = (/1.0_dp,0.0_dp,0.0_dp/)
      y = -cross_product(x, uvw)

      ! Ray tracing : on se propage dans l'autre sens
      u0 = -u ; v0 = -v ; w0 = -w

      call gauss_legendre_quadrature(0.0_dp, 1.0_dp, Nmu, cos_theta, weight_mu)

      !!!$omp parallel &
      !!!$omp default(none) &
      !!!$omp private(j,i,id,u0,v0,w0,lintersect,icell0) &
      !!!$omp shared(Imu, Imuc, u,v,w,Rmax,iray,labs,Itot, Icont)
      do j=1,Nmu
         !!!$ id = omp_get_thread_num() + 1

         rr = Rmax * sqrt(1.0 - cos_theta(j)**2)
         !rr = Rmax * real(j-1)/real(Nmu-1)
         !cos_theta(j) = sqrt(1.0 - (rr/Rmax)**2)

         x0 = 10.0*Rmax*u + rr * sin(phi) * x(1) + rr * cos(phi) * y(1)
         y0 = 10.0*Rmax*v + rr * sin(phi) * x(2) + rr * cos(phi) * y(2)
         z0 = 10.0*Rmax*w + rr * sin(phi) * x(3) + rr * cos(phi) * y(3)

         call move_to_grid(id,x0,y0,z0,u0,v0,w0,icell0,lintersect)

         !cos_theta(j)  = abs(x0*u + y0*v + z0*w) / sqrt(z0*z0 + x0*x0 + y0*y0)
         p(j) = rr*AU_to_rsun

         if (cos_theta(j) < 0.05) then
               if( (icell0 > n_cells).or.(icell0 < 1) ) then
               call warning("for this cos(theta) the ray is put in the star! check prec grid")
               write(*,*) "cos(theta)=",cos_theta(j), " icell=", icell0, " intersect?:", lintersect
               cycle !because of prec grid ??
            endif
         endif

         if (lintersect) then ! On rencontre la grille, on a potentiellement du flux
            call integ_ray_line(id, icell0, x0,y0,z0,u0,v0,w0,iray,labs)
            Imu(:,j,1) = Itot(:,iray,id)
            Imuc(:,j,1) = Icont(:,iray,id)
            if (lmagnetized) then
               IQ(:,j,1) = Stokes_Q(:,id)
               IU(:,j,1) = Stokes_U(:,id)
               IV(:,j,1) = Stokes_V(:,id)
            endif
         endif
      enddo
      !!!$omp end do
      !!!$omp end parallel

      open(unit=14,file="Imu.s",status="unknown")
      open(unit=15,file="Imuc.s",status="unknown")
      write(14,*) Nlambda, Nmu, 1
      write(15,*) Nlambda_cont, Nmu, 1
      write(14,'(*(E20.7E3))') (p(j), j=1,Nmu)
      write(15,'(*(E20.7E3))') (p(j), j=1,Nmu)
      write(14,'(*(E20.7E3))') (cos_theta(j), j=1,Nmu)
      write(15,'(*(E20.7E3))') (cos_theta(j), j=1,Nmu)
      do i=1,Nlambda
         if (lmagnetized) then
            write(14,'(1F12.5, *(E20.7E3))') lambda(i), (Imu(i,j,1),  j=1,Nmu), &
               (IQ(i,j,1),  j=1,Nmu), (IU(i,j,1),  j=1,Nmu), (IV(i,j,1),  j=1,Nmu)
         else
            write(14,'(1F12.5, *(E20.7E3))') lambda(i), (Imu(i,j,1),  j=1,Nmu)
         endif
      enddo
      do i=1,Nlambda_cont
         write(15,'(1F12.5, *(E20.7E3))') lambda_cont(i), (Imuc(i,j,1),  j=1,Nmu)
      enddo
      close(14)
      close(15)
      deallocate(weight_mu, cos_theta, p, Imu, Imuc,q)
      if (lmagnetized) then
         deallocate(IQ,IU,IV)
      endif

      return
   end subroutine compute_Imu

  
end module atom_transfer
 ! subroutine compute_contribution_functions
   !    !for one ray at the centre of the image
   !    !unpolarised case at the moment.
   !    !not para yet
   !    ! Does not include non opacities of the continuum
   !       real(kind=dp) :: u, v, w !, intent(in)
   !       integer :: ibin, iaz
   !       integer, parameter :: unit_cf = 10
   !       character(len=512) :: filename, string1, string2, fname_cont
   !       integer :: id, icell0, icell, iray
   !       real(kind=dp) :: x0,y0,z0,u0,v0,w0
   !       logical :: lintersect, labs
   !     ! 		integer :: max_length
   
   !     ibin = 1; iaz = 1
   !     id = 1
   !     labs = .false.
   !     iray = 1
   !     ! 		filename = "cntrb_ray.s"
   
   !     write(*,*) "   Computing contribution function at centre of the image..."
   !     write(*,*) "      for all directions."
       
   !     if (NactiveAtoms > 0) then
   !        call Warning("Missing Non-LTE continuum opacities in CF rays")
   !     endif
   
   !    do ibin=1,RT_n_incl
   !        do iaz=1,RT_n_az
   
   !           u = tab_u_RT(ibin,iaz) ;  v = tab_v_RT(ibin,iaz) ;  w = tab_w_RT(ibin)
   
   !           ! Ray tracing : on se propage dans l'autre sens
   !           u0 = -u ; v0 = -v ; w0 = -w
   !           x0 = 10*Rmax*u; y0 = 10*Rmax*v; z0 = 10*Rmax*w
   
   
   !           call move_to_grid(id,x0,y0,z0,u0,v0,w0,icell0,lintersect)
   
   
   !           if (lintersect) then
   !              ! 					write(filename, '("cntrb_ray_i"(1I2)"_a"(1I2)".s")') nint(tab_rt_incl(ibin)), nint(tab_rt_az(iaz))
   !              write(string1,'(1I4)') nint(tab_rt_incl(ibin))
   !              write(string2,'(1I4)') nint(tab_rt_az(iaz))
   !              filename = "cntrb_ray_i"//trim(adjustl(string1))//"_a"//trim(adjustl(string2))//".s"
   !              open(unit_cf, file=filename, status="unknown")
   !              fname_cont = "cntrb_ray_cont_i"//trim(adjustl(string1))//"_a"//trim(adjustl(string2))//".s"
   !              open(unit_cf+1, file=fname_cont, status="unknown")
   !              call integ_ray_cntrb(id,icell0,x0,y0,z0,u0,v0,w0,iray,labs,unit_cf)
   !              close(unit_cf)
   !              close(unit_cf+1)
   !           else
   !              write(*,*) "Nothing in this direction, cntrb_ray = 0"
   !              ! 					return
   !              cycle
   !           endif
   !        enddo
   !     enddo
   
   
   !       return
   !    end subroutine compute_contribution_functions
   
   !   subroutine integ_ray_cntrb(id,icell_in,x,y,z,u,v,w,iray,labs,unit_cf)
   !     ! ------------------------------------------------------------------------------- !
   !     !
   !     ! ------------------------------------------------------------------------------- !
   
   !     integer, intent(in) :: id, icell_in, iray
   !     real(kind=dp), intent(in) :: u,v,w
   !     real(kind=dp), intent(in) :: x,y,z
   !     logical, intent(in) :: labs
   !     real(kind=dp) :: x0, y0, z0, x1, y1, z1, l, l_contrib, l_void_before
   !     real(kind=dp), dimension(Nlambda) :: tau, dtau, etas_loc
   !     real(kind=dp), dimension(Nlambda_cont) :: tau_c, dtau_c, etasc_loc
   !     real(kind=dp) :: xmass, l_tot
   !     integer, intent(in) :: unit_cf
   !     integer :: nbr_cell, icell, next_cell, previous_cell, icell_star, i_star, la, icell_prev
   !     logical :: lcellule_non_vide, lsubtract_avg, lintersect_stars
   
   !     write(unit_cf,*) Nlambda
   !     write(unit_cf+1,*) Nlambda_cont
   
   !     x1=x;y1=y;z1=z
   !     x0=x;y0=y;z0=z
   !     next_cell = icell_in
   !     nbr_cell = 0
   
   !     tau(:) = 0.0_dp
   !     xmass = 0.0_dp
   !     l_tot = 0.0_dp
   !     Icont(:,1,id) = 0.0_dp
   
   !     tau_c = 0.0
   !     dtau_c = 0.0
       
   !     etasc_loc(:) = 0.0_dp
   !     etas_loc(:) = 0.0_dp
   
   !     icell_prev = icell_in
   
   !     call intersect_stars(x,y,z, u,v,w, lintersect_stars, i_star, icell_star)
   
   
   !     infinie : do
   
   !        icell = next_cell
   !        x0=x1 ; y0=y1 ; z0=z1
   
   !        if (icell <= n_cells) then
   !           lcellule_non_vide=.true.
   !           if (icell > 0) then
   !              lcellule_non_vide = (icompute_atomRT(icell) > 0)
   !              if (icompute_atomRT(icell) < 0) return !-1 if dark
   !           endif
   !        else
   !           lcellule_non_vide=.false.
   !        endif
   
   
   !        if (test_exit_grid(icell, x0, y0, z0)) return
   
   !        if (lintersect_stars) then!only cont
   !          !  Icont(:,1,id) =  Icont(:,1,id) + exp(-tau_c) * Istar_cont(:,i_star) * &
   !                ! local_stellar_brigthness(Nlambda_cont,lambda_cont,i_star, icell_prev,x0, y0, z0, u,v,w)
   !          call local_stellar_radiation(id,1,tau,tau_c,i_star,icell_prev,x,y,z,u,v,w)
   !           if (icell == icell_star) return
   !        endif
   
   !       !-> test for Voronoi here ?
   !        ! 			if (icell <= n_cells) then
   !        ! 				lcellule_non_vide = (icompute_atomRT(icell) > 0)
   !        ! 				if (icompute_atomRT(icell) < 0) return !-1 if dark
   !        ! 			endif
   
   !        nbr_cell = nbr_cell + 1
   
   !        previous_cell = 0
   !        call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell,l, l_contrib, l_void_before)
   
   !        if (lcellule_non_vide) then
   !           lsubtract_avg = ((nbr_cell == 1).and.labs)
   
   !           !Total source fonction or set eta to 0 to have only line emissivity
   !           if (llimit_mem) then
   !              call interp_continuum_local(icell, chi(:,id), eta(:,id))
   !           else
   !              chi(:,id) = chi0_bb(:,icell)
   !              eta(:,id) = eta0_bb(:,icell)
   !           endif
   !           if (lelectron_scattering) then
   !              etasc_loc = Jnu_cont(:,icell) * (thomson(icell) + HI_rayleigh_part1(icell) * HI_rayleigh_part2(:))
   !              if (associated(helium)) then
   !                 etasc_loc = etasc_loc + Jnu_cont(:,icell) * HeI_rayleigh_part1(icell) * HeI_rayleigh_part2(:)
   !              endif
   !              etas_loc = linear_1D_sorted(Nlambda_cont,lambda_cont,etasc_loc, Nlambda,lambda)
   !          etas_loc(Nlambda) = etasc_loc(Nlambda_cont)
            
   !              dtau_c(:) = l_contrib * chi_c(:,icell) * AU_to_m
   !              Icont(:,1,id) = Icont(:,1,id) + (eta_c(:,icell)+etasc_loc(:))/chi_c(:,icell) * exp(-tau_c) * (1.0 - exp(-dtau_c))
   !              tau_c(:) = tau_c(:) + dtau_c(:)
   !         else
   !              dtau_c(:) = l_contrib * chi_c(:,icell) * AU_to_m
   !              Icont(:,1,id) = Icont(:,1,id) + eta_c(:,icell)/chi_c(:,icell) * exp(-tau_c) * (1.0 - exp(-dtau_c))
   !              tau_c(:) = tau_c(:) + dtau_c(:)
   !           endif
   
   !           !includes a loop over all bound-bound, passive and active
   !           call opacity_atom_loc(id,icell,iray,x0,y0,z0,x1,y1,z1,u,v,w,l_void_before,l_contrib,.false.)
   
   !           dtau(:) = l_contrib * chi(:,id) * AU_to_m
   
   !           if (lelectron_scattering) then
   !              eta(:,id) = eta(:,id) + etas_loc(:)
   !           endif
   
   !           tau = tau + dtau
   !           l_tot = l_tot + l_contrib * AU_to_m
   !           xmass = xmass + l_contrib * AU_to_m *  nHtot(icell) * masseH * 1d-3
   
   
   !           write(unit_cf, '(1I, 4ES17.8E3, 2F12.5)') icell, l_tot, xmass, nHtot(icell), ne(icell), T(icell), &
   !                sqrt(x0*x0+y0*y0+z0*z0)/etoile(1)%r
   !           write(unit_cf+1, '(1I, 4ES17.8E3, 2F12.5)') icell, l_tot, xmass, nHtot(icell), ne(icell), T(icell), &
   !                sqrt(x0*x0+y0*y0+z0*z0)/etoile(1)%r
   !           ! 				write(*,*) 'icell=', icell, ne(icell), nHtot(icell), ' T=', T(icell)
   !           if (llimit_mem) then
   !              do la=1, Nlambda
   !                 write(unit_cf,'(1F12.5, 6ES17.8E3)') lambda(la), tau(la), eta(la,id)*E2(tau(la)), tau(la)*exp(-tau(la)), eta(la,id)/(1d-50 + chi(la,id)), chi(la,id)/tau(la), Icont(la,1,id) - eta(la,id)/(1d-50 + chi(la,id))
   !              enddo!
   !           else
   !              do la=1, Nlambda
   !                 write(unit_cf,'(1F12.5, 6ES17.8E3)') lambda(la), tau(la), eta(la,id)*E2(tau(la)), &
   !                      tau(la)*exp(-tau(la)), eta(la,id)/(tiny_dp + chi(la,id)), chi(la,id)/tau(la), &
   !                      (eta(la,id)-eta0_bb(la,icell))/(max(1d-50,chi(la,id)-chi0_bb(la,icell)))
   !              enddo
   !           endif
   !           do la=1, Nlambda_cont
   !              write(unit_cf+1,'(1F12.5, 6ES17.8E3)') lambda_cont(la), tau_c(la), eta_c(la,icell)*E2(tau_c(la)), &
   !                   tau_c(la)*exp(-tau_c(la)), eta_c(la,icell)/chi_c(la,icell), chi_c(la,icell)/tau_c(la), Icont(la,1,id)
   !           enddo
   
   
   
   !        end if
   !        icell_prev = icell
   !     end do infinie
   
   !     return
   !   end subroutine integ_ray_Cntrb

  !   	subroutine integ_ray_cntrb(id,icell_in,x,y,z,u,v,w,iray,labs)
  ! 	! ------------------------------------------------------------------------------- !
  ! 	!
  ! 	! ------------------------------------------------------------------------------- !
  !
  ! 		integer, intent(in) :: id, icell_in, iray
  ! 		real(kind=dp), intent(in) :: u,v,w
  ! 		real(kind=dp), intent(in) :: x,y,z
  ! 		logical, intent(in) :: labs
  ! 		real(kind=dp) :: x0, y0, z0, x1, y1, z1, l, l_contrib, l_void_before
  ! 		real(kind=dp), dimension(Nlambda) :: tau, dtau!,etal, chil
  ! 		integer :: nbr_cell, icell, next_cell, previous_cell, icell_star, i_star, la
  ! 		logical :: lcellule_non_vide, lsubtract_avg, lintersect_stars
  !
  ! 		x1=x;y1=y;z1=z
  ! 		x0=x;y0=y;z0=z
  ! 		next_cell = icell_in
  ! 		nbr_cell = 0
  !
  ! 		tau(:) = 0.0_dp
  !
  !
  ! 		call intersect_stars(x,y,z, u,v,w, lintersect_stars, i_star, icell_star)
  !
  !
  ! 		infinie : do
  !
  ! 			icell = next_cell
  ! 			x0=x1 ; y0=y1 ; z0=z1
  !
  ! 			if (icell <= n_cells) then
  ! 				lcellule_non_vide=.true.
  ! 				if (icell > 0) then
  ! 					lcellule_non_vide = (icompute_atomRT(icell) > 0)
  ! 					if (icompute_atomRT(icell) < 0) return !-1 if dark
  ! 				endif
  ! 			else
  ! 				lcellule_non_vide=.false.
  ! 			endif
  !
  !
  ! 			if (test_exit_grid(icell, x0, y0, z0)) return
  !
  ! 			if (lintersect_stars) then
  ! 				if (icell == icell_star) return
  !    			 endif
  !
  ! ! 			if (icell <= n_cells) then
  ! ! 				lcellule_non_vide = (icompute_atomRT(icell) > 0)
  ! ! 				if (icompute_atomRT(icell) < 0) return !-1 if dark
  ! ! 			endif
  !
  ! 			nbr_cell = nbr_cell + 1
  !
  ! 			previous_cell = 0
  ! 			call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell,l, l_contrib, l_void_before)
  !
  ! 			if (lcellule_non_vide) then
  ! 				lsubtract_avg = ((nbr_cell == 1).and.labs)
  !
  ! 				l_contrib = l_contrib * AU_to_m
  !
  ! 				!Total source fonction or set eta to 0 to have only line emissivity
  ! 				chi(:,id) = chi0_bb(:,icell)
  ! 				eta(:,id) = eta0_bb(:,icell)
  !
  ! 				!includes a loop over all bound-bound, passive and active
  ! 				call opacity_atom_loc(id,icell,iray,x0,y0,z0,x1,y1,z1,u,v,w,l,.false.)
  !
  ! 				dtau(:) = l_contrib * chi(:,id)
  !
  ! 				if (lelectron_scattering) then
  ! 					eta(:,id) = eta(:,id) + thomson(icell)*Jnu(:,icell)
  ! 				endif
  !
  ! 				!Use etal only ?  here I plot dI/dr integrated over directions
  ! 				!S_contrib(:,icell,id) =  eta(:,id) * exp(-tau(:)) !or S * -dtau/dr = S * dtau/l_contrib
  ! 				do la=1, Nlambda
  ! 					if (tau(la) > 0) cntrb_ray(la,icell) = eta(la,id) * E2(tau(la))!exp(-tau(:))
  ! 					!->Flow chart
  ! 					!cntrb_ray(la,icell) = ( eta(la,id)/chi(la,id) ) * (1.0_dp - exp(-dtau(la))) * exp(-tau(la))
  ! 				enddo
  !
  !
  ! 				tau = tau + dtau
  ! 				tau_one_ray(:,icell) = tau(:)*exp(-tau(:))
  !
  ! 			end if
  ! 		end do infinie
  !
  ! 	return
  ! 	end subroutine integ_ray_Cntrb

  !  subroutine calc_stellar_surface_brightness(N,lambda,i_star,icell_prev,x,y,z,u,v,w,gamma)
  !  ! ---------------------------------------------------------------!
  !   ! Compute the stellar radiation field surface brightness.
  !   ! Istar = B(x,y,z;mu) * Stellar spectrum or B * BlackBody
  !   ! return gamma, the brightness. For uniform disk, gamma is 1.
  !   !
  !   ! If there is a shock spot at the surface, gamma returned is :
  !   ! gamma = 1 + ratio, such that the radiation from the star Istar is
  !   ! Istar = I(photosphere) + Ishock, with Ishock = I(photosphere) * ratio.
  !   ! (previously, Istar was Ishock, now it is the sum of the two contrib)
  !  ! -------------------------------------------------------------- !
  !   integer, intent(in) :: N, i_star, icell_prev
  !   real(kind=dp), dimension(N), intent(in) :: lambda
  !   real(kind=dp), dimension(N), intent(out) :: gamma
  !   real(kind=dp), intent(in) :: u, v, w, x, y, z
  !   real(kind=dp) :: energie(N), Tchoc
  !   real(kind=dp) :: mu, ulimb, LimbDarkening, surface, HC
  !   integer :: ns,la
  !   logical :: lintersect = .false.
  !
  !    if (etoile(i_star)%T <= 1e-6) then !even with spots
  !     gamma(:) = 0.0_dp
  !     return !no radiation from the starr
  !    endif
  !
  !    gamma(:) = 1.0_dp !init
  !    					 !if no spots (and no other sources like X rays, UV flux)
  !    					 !it is the outvalue
  !
  !    !if (ladd_xrays) then
  !     !such that Ixray = Iphot * gamma and Istar = Iphot + Ixray = Iphot * (1 + gamma)
  ! !     gamma(:) = gamma(:) + (exp(hc_k/lambda/etoile(i_star)%T)-1)/(exp(hc_k/lambda/1d6)-1)
  ! !     where (lambda <= 50.)
  ! !         gamma(:) = gamma(:) + (exp(hc_k/lambda/etoile(i_star)%T)-1)/(exp(hc_k/lambda/1d6)-1)
  ! !     end where
  !    !endif
  !
  !    !cos(theta) = dot(r,n)/module(r)/module(n)
  !    mu = abs(x*u + y*v + z*w)/sqrt(x**2+y**2+z**2) !n=(u,v,w) is normalised
  !    if (real(mu)>1d0) then !to avoid perecision error
  !     write(*,*) "mu=",mu, x, y, z, u, v, w
  !     call Error(" mu limb > 1!")
  !    end if
  !
  !
  !   ! Correct with the contrast gamma of a hotter/cooler region if any
  ! !    call intersect_spots(i_star,u,v,w,x,y,z, ns,lintersect)
  ! !    !avoid error with infinity for small lambda
  ! !    if (lintersect) then
  ! !    		!Means that Ispot = Bp(Tspot) = gamma * Iphot  = Ispot
  ! !    		!gamma is initialized to one here.
  ! !    		!The +1 (i.e., the gamma = gamma + ...) means that Istar = Iphot + Ispot = Iphot * (1 + gamma)
  ! ! 		gamma(:) = gamma(:) + (exp(hc_k/max(lambda,10.0)/etoile(i_star)%T)-1)/(exp(hc_k/max(lambda,10.0)/etoile(i_star)%SurfB(ns)%T)-1)
  ! !      !so that I_spot = Bplanck(Tspot) = Bp(Tstar) * gamma = Bp(Tstar)*B_spot/B_star
  ! !      	!Lambda independent spots, Ts = 2*Tphot means Fspot = 2 * Fphot
  ! !  		!gamma = gamma + (etoile(i_star)%SurfB(ns)%T - etoile(i_star)%T) / etoile(i_star)%T
  ! !    end if
  !
  !    if ((laccretion_shock).and.(icell_prev<=n_cells)) then
  !    	if (icompute_atomRT(icell_prev)) then
  !    		if (vr(icell_prev) < 0.0_dp) then
  ! !    		write(*,*) "Accretion E (K):", (1d-3 * masseH * wght_per_H * nHtot(icell_prev)*abs(vr(icell_prev))/sigma * (0.5 * (vr(icell_prev)**2+v_z(icell_prev)**2+vphi(icell_prev)**2)))**0.25
  ! !    			lintersect = .true.
  !    			if (Taccretion>0) then
  !    				Tchoc = Taccretion
  !    			else!need a condition to use vtheta or vphi. Or an array that contains for each cell Tshock or zero (only for cell close to the star)
  !    				Tchoc = (1d-3 * masseH * wght_per_H * nHtot(icell_prev)*abs(vr(icell_prev))/sigma * (0.5 * (vr(icell_prev)**2+v_z(icell_prev)**2+vphi(icell_prev)**2)))**0.25
  !    			endif
  ! !    			if (Taccretion>0) then
  ! !    				Tchoc = Taccretion
  ! !    			else!need a condition to use vtheta or vphi. Or an array that contains for each cell Tshock or zero (only for cell close to the star)
  ! !    				Tchoc = (1d-3 * masseH * wght_per_H * nHtot(icell_prev)*abs(vr(icell_prev))/sigma * (0.5 * (vr(icell_prev)**2+v_z(icell_prev)**2+vphi(icell_prev)**2)))**0.25
  ! !    			endif
  !    			lintersect = (Tchoc > etoile(i_star)%T)
  !    		endif
  ! 	endif !rho > 0
  ! 	if (lintersect) then
  ! ! 		write(*,*) "intersect spot"
  ! 		gamma(:) = gamma(:) + (exp(hc_k/max(lambda,10.0)/etoile(i_star)%T)-1)/(exp(hc_k/max(lambda,10.0)/Tchoc)-1)
  ! 	endif
  !
  !    endif!cells <= n_cells
  !
  !
  !    !Apply Limb darkening
  !    if (llimb_darkening) then
  !      call ERROR("option for reading limb darkening not implemented")
  !    else
  !      !ulimb = 0.6
  !      LimbDarkening = 1.0_dp!0.4 + 0.6 * mu!1.0_dp
  !    end if
  !    !Istar(:) = energie(:) * LimbDarkening * gamma(:)
  !    gamma(:) = LimbDarkening * gamma(:)
  !
  !  return
  !  end subroutine calc_stellar_surface_brightness

  !building
!   subroutine NLTEloop(n_rayons_max,n_rayons_1,n_rayons_2,maxIter,verbose)
!     ! -------------------------------------------------------- !
!     ! Descriptor here
!     ! -------------------------------------------------------- !
! #include "sprng_f.h"
!     integer, intent(in) :: n_rayons_1, n_rayons_2, maxIter, n_rayons_max
!     logical, intent(in) :: verbose
    ! 		integer, parameter :: max_sub_iter = 10000, max_global_iter = 1000
    ! 		integer :: etape, etape_start, etape_end, iray, n_rayons, iray_p
    ! 		integer :: n_iter, n_iter_loc, id, i, iray_start, alloc_status, la, kr
    ! 		integer, dimension(nb_proc) :: max_n_iter_loc
    ! 		logical :: lfixed_Rays, lnotfixed_Rays, lconverged, lconverged_loc, lprevious_converged
    ! 		real :: rand, rand2, rand3, precision, precision_sub
    ! 		real(kind=dp) :: x0, y0, z0, u0, v0, w0, w02, srw02, argmt, smu
    ! 		real(kind=dp) :: diff, norme, dN, dN1, dJ, lambda_max
    ! 		real(kind=dp) :: dT, dN2, dN3, diff_old
    ! 		real(kind=dp), allocatable :: dTM(:), dM(:), Tion_ref(:), Tex_ref(:)
    ! 		real(kind=dp), allocatable :: Jnew(:,:), Jold(:,:), Jnew_cont(:,:)
    ! 		logical :: labs, iterate_ne = .false.
    ! 		logical :: l_iterate
    ! 		integer :: nact, imax, icell_max, icell_max_2
    ! 		integer :: icell, ilevel, imu, iphi
    ! 		character(len=20) :: ne_start_sol = "NE_MODEL"
    ! 		type (AtomType), pointer :: atom
    !
    ! 		open(unit=unit_invfile, file=trim(invpop_file), status="unknown")
    ! 		write(unit_invfile,*) n_cells
    ! 		open(unit=unit_profiles, file=trim(profiles_file), status="unknown")
    !
    ! 		allocate(gpop_old(NactiveAtoms,Nmaxlevel,n_cells),stat=alloc_status)
    ! 		if (alloc_status > 0) call error("Allocation error gpop_old")
    ! 		gpop_old(:,:,:) = 0.0_dp
    ! 		do nact=1,NactiveAtoms
    ! 			atom => ActiveAtoms(nact)%ptr_atom
    ! 			gpop_old(nact,1:atom%Nlevel,:) = atom%n(:,:)
    ! 			atom => NULL()
    ! 		enddo
    !
    ! 		allocate(n_new(NactiveAtoms,Nmaxlevel,n_cells),stat=alloc_status)
    ! 		if (alloc_status > 0) call error("Allocation error n_new")
    ! 		n_new(:,:,:) = 0.0_dp
    ! 		allocate(dM(Nactiveatoms)); dM=0d0 !keep tracks of dpops for all cells for each atom
    ! 		allocate(dTM(Nactiveatoms)); dM=0d0 !keep tracks of Tex for all cells for each atom
    ! 		allocate(Jnew(Nlambda, n_cells)); Jnew = 0.0
    ! 		allocate(Jold(Nlambda, n_cells)); Jold = 0.0
    ! 		allocate(Jnew_cont(Nlambda_cont, n_cells)); Jnew_cont = 0.0
    ! 		allocate(Tex_ref(Nactiveatoms)); dM=0d0 !keep tracks of max Tex for all cells for each line of each atom
    ! 		allocate(Tion_ref(Nactiveatoms)); dM=0d0 !keep tracks of max Tion for all cells for each cont of each atom
    ! 		diff_old = 0.0_dp
    !
    !
    ! 		labs = .true. !to have ds at cell icell = eval_operator
    ! 		id = 1
    ! 		etape_start = 2
    ! 		if (laccurate_integ) then
    ! 			write(*,*) " Using step 3 with ", n_rayons_max, " nrays max"
    ! 			etape_end = 3
    ! 		else
    ! 			etape_end = 2
    ! 		endif
    !
    !
    ! 		iterate_ne = (n_iterate_ne>0)
    ! 		if (iterate_ne) then
    ! 			write(*,*) " before iterate ne I need te recompute gij for continua !!"
    ! 		endif
    !
    ! 		do etape=etape_start, etape_end
    !
    ! 			if (etape==1) then
    ! 				write(*,*) " step 1 not implemented"
    ! 				stop
    ! 			else if (etape==2) then
    ! 				lfixed_rays = .true.
    ! 				n_rayons = n_rayons_1
    ! 				iray_start = 1
    ! 				lprevious_converged = .false.
    ! 				lcell_converged(:) = .false.
    ! 				precision = dpops_max_error
    ! 				precision_sub = dpops_sub_max_error
    ! 			else if (etape==3) then
    ! 		  		lfixed_rays = .false.
    !   				n_rayons = n_rayons_2
    !   				lprevious_converged = .false.
    ! 				lcell_converged(:) = .false.
    ! 				precision = 1e-1 !dpops_max_error
    ! 				precision_sub = dpops_sub_max_error
    ! 			else
    ! 				call ERROR("etape unkown")
    ! 			end if
    !
    ! 			write(*,*)  "-> Using ", n_rayons, ' rays for step', etape
    !
    ! 			lnotfixed_rays = .not.lfixed_rays
    ! 			lconverged = .false.
    ! 			n_iter = 0
    !
    ! 			do while (.not.lconverged)
    !
    ! 				n_iter = n_iter + 1
    ! 				!if (n_iter > max_global_iter) exit !change step !maxIter
    ! 				write(*,*) " -> Iteration #", n_iter, " Step #", etape
    !
    ! 				if (lfixed_rays) then
    ! 					stream = 0.0
    ! 					do i=1,nb_proc
    ! 						stream(i) = init_sprng(gtype, i-1,nb_proc,seed,SPRNG_DEFAULT)
    ! 					end do
    ! 				end if
    !
    ! 				max_n_iter_loc = 0
    !
    !
    ! 				!$omp parallel &
    ! 				!$omp default(none) &
    ! 				!$omp private(id,iray,rand,rand2,rand3,x0,y0,z0,u0,v0,w0,w02,srw02, la, dM, dN, dN1,iray_p,imu,iphi, smu)&
    ! 				!$omp private(argmt,n_iter_loc,lconverged_loc,diff,norme, icell, nact, atom, l_iterate) &
    ! 				!$omp shared(icompute_atomRT, dpops_sub_max_error, verbose,lkeplerian,n_iter,precision_sub,threeKminusJ,stest_tot) &
    ! 				!$omp shared(stream,n_rayons,iray_start, r_grid, z_grid,lcell_converged,loutput_rates,xyz_pos,uvw_pos, gtype, seed, nb_proc) &
    ! 				!$omp shared(n_cells, gpop_old,lforce_lte, integ_ray_line, Itot, Icont, Jnu_cont, Jnu) &
    ! 				!$omp shared(Jnew, Jnew_cont, Jold, lelectron_scattering,chi0_bb, etA0_bb, activeatoms,n_new) &
    ! 				!$omp shared(nHmin, chi_c, chi_c_nlte, eta_c, eta_c_nlte, ds, Rij_all, Rji_all, Nmaxtr, Gammaij_all, Nmaxlevel) &
    ! 				!$omp shared(lfixed_Rays,lnotfixed_Rays,labs,max_n_iter_loc, etape,pos_em_cellule,Nactiveatoms)
    ! 				!$omp do schedule(static,1)
    ! 				do icell=1, n_cells
    ! 					!$ id = omp_get_thread_num() + 1
    ! ! 					if (lfixed_rays) then
    !    						l_iterate = (icompute_atomRT(icell)>0)
    ! ! 					else
    ! !    						l_iterate = (icompute_atomRT(icell)>0).and.(.not.lcell_converged(icell))
    ! ! 					endif
    !    					if (l_iterate) then
    !    						Jnew(:,icell) = 0.0
    !    						Jnew_cont(:,icell) = 0.0
    !    						threeKminusJ(:,icell) = 0.0
    ! 					!!if (atmos%icompute_atomRT(icell)>0) then
    !
    ! 						call fill_Collision_matrix(id, icell) !computes = C(i,j) before computing rates
    ! 						call initGamma(id) !init Gamma to C and init radiative rates
    !
    ! 						do iray=iray_start, iray_start-1+n_rayons
    !
    ! 							if ( (etape==2).or.(etape==3) ) then
    !                    	    ! Position aleatoire dans la cellule
    !
    ! 								rand  = sprng(stream(id))
    ! 								rand2 = sprng(stream(id))
    ! 								rand3 = sprng(stream(id))
    !
    ! 								call  pos_em_cellule(icell ,rand,rand2,rand3,x0,y0,z0)
    !
    !                         ! Direction de propagation aleatoire
    ! 								rand = sprng(stream(id))
    ! 								W0 = 2.0_dp * rand - 1.0_dp !nz
    ! 								W02 =  1.0_dp - W0*W0 !1-mu**2 = sin(theta)**2
    ! 								SRW02 = sqrt(W02)
    ! 								rand = sprng(stream(id))
    ! 								ARGMT = PI * (2.0_dp * rand - 1.0_dp)
    ! 								U0 = SRW02 * cos(ARGMT) !nx = sin(theta)*cos(phi)
    ! 								V0 = SRW02 * sin(ARGMT) !ny = sin(theta)*sin(phi)
    !
    ! 								call integ_ray_line(id, icell, x0, y0, z0, u0, v0, w0, iray, labs)
    ! 								Jnew(:,icell) = Jnew(:,icell) + Itot(:,iray,id)
    ! 								Jnew_cont(:,icell) = Jnew_cont(:,icell) + Icont(:,id)
    ! 								threeKminusJ(:,icell) = threeKminusJ(:,icell) + (3.0 * (u0*x0+v0*y0+w0*z0)**2/(x0**2+y0**2+z0**2) - 1.0) * Itot(:,iray,id)
    !
    ! 							elseif (etape==1) then
    ! 								stop
    ! 							end if !etape
    !
    ! 						enddo !iray
    ! 						Jnew(:,icell) = Jnew(:,icell) / n_rayons
    ! 						Jnew_cont(:,icell) = Jnew_cont(:,icell) / n_rayons
    ! 						threeKminusJ(:,icell) = threeKminusJ(:,icell) / n_rayons
    ! 						!!if (lelectron_scattering) then
    ! 						!!always allocated if nlte ?, need to change that but remember we need
    ! 						!! in the nlte loop, to write the full mean intensity to fits file.
    ! 							eta_es(:,icell) = Jnew(:,icell) * thomson(icell)
    ! 						!!endif
    !
    ! 						if (loutput_Rates) &
    ! 							call store_radiative_rates(id, icell, n_rayons, Nmaxtr, Rij_all(:,:,icell), Rji_all(:,:,icell), Jnew(:,icell),.false.)
    !
    ! 						if (lforce_lte) then
    ! 							call update_populations(id, icell, diff, .false., n_iter)
    ! 							lconverged_loc = .true.
    ! 						else
    ! 							lconverged_loc = .false.
    ! 							do iray=1,n_rayons !-> including n_new
    ! 								call calc_rates(id, icell, iray, n_rayons)
    ! 							enddo
    ! 							call calc_rate_matrix(id, icell, lforce_lte)
    ! 						endif
    !
    ! 						n_iter_loc = 0
    !      				!!only iterate on cells which are not converged
    ! 						do while (.not.lconverged_loc)
    ! 							n_iter_loc = n_iter_loc + 1
    !
    ! 							if ((mod(n_iter_loc,max(1,1000))==0)) then
    ! 								write(*,*) " -- Global iteration #", n_iter, " step #", etape, "eps: ", dpops_sub_max_error
    ! 							endif!(mod(n_iter_loc,max(1,max_sub_iter/10))==0)
    ! 							call update_Populations(id, icell, diff,(mod(n_iter_loc,max(1,1000))==0),n_iter_loc)
    ! 							if ((mod(n_iter_loc,max(1,1000))==0)) write(*,*) " --------------------------------------------------------------- "
    !
    !
    !                         !for this icell (id) and local iteration
    ! 							if (diff < precision_sub) then
    ! 								lconverged_loc = .true.
    !      					    !write(*,*) "converged", id, icell, "dpops(sub) = ", diff
    ! 							else
    ! !need to include cont nlte
    ! 								call initGamma(id)
    ! ! 								call interp_continuum_local(icell, chi0_bb(:,icell), eta0_bb(:,icell))
    ! 								do iray=1,n_rayons
    ! 									call calc_rates(id, icell, iray, n_rayons)
    ! 								enddo
    !
    ! 								call calc_rate_matrix(id, icell, lforce_lte)
    !
    ! 							end if
    !
    ! 						end do !local sub iteration
    ! 						if (n_iter_loc > max_n_iter_loc(id)) max_n_iter_loc(id) = n_iter_loc
    ! 						if (loutput_Rates) &
    ! 							call store_rate_matrices(id,icell,Nmaxlevel,Gammaij_all(:,:,:,icell))
    ! 					end if !icompute_atomRT
    ! 				end do !icell
    ! 				!$omp end do
    ! 				!$omp end parallel
    !
    !      		!Global convergence Tests
    !
    !             !should be para
    ! 				dM(:) = 0.0
    ! 				diff = 0.0
    ! 				dJ = 0.0
    ! 				dT = 0.0
    ! 				dTM(:) = 0.0
    ! 				Tex_ref(:) = 0.0
    ! 				Tion_ref(:) = 0.0
    !    				icell_max = 1
    !    				icell_max_2 = 1
    ! 				cell_loop2 : do icell=1,n_cells
    ! ! 					if (lfixed_rays) then
    !    						l_iterate = (icompute_atomRT(icell)>0)
    ! ! 					else
    ! !    						l_iterate = (icompute_atomRT(icell)>0).and.(.not.lcell_converged(icell))
    ! ! 					endif
    !    					if (l_iterate) then
    ! 						dN = 0.0 !for all levels of all atoms of this cell
    ! 						dN2 = 0.0
    ! 						do nact=1,NactiveAtoms
    ! 							atom => ActiveAtoms(nact)%ptr_atom
    !
    ! 							do ilevel=1,atom%Nlevel
    ! 								!if (atom%n(ilevel,icell) > 0) then
    ! 								dN1 = abs(1d0-atom%n(ilevel,icell)/n_new(nact,ilevel,icell))
    ! ! 								dN1 = abs(1d0-gpop_old(nact,ilevel,icell)/atom%n(ilevel,icell))
    !      				    		!dN1 = abs(atom%n(ilevel,icell)-gpop_old(nact,ilevel,icell))/(gpop_old(nact,ilevel,icell)+tiny_dp)
    ! 								dN = max(dN1, dN) !compare with all atoms and levels
    !      				    						  !for this cell
    ! 								dM(nact) = max(dM(nact), dN1) !compare for one atom
    !      				    		 							   !for all cells
    ! 								!endif
    ! 								!!write(*,*) "pops", dN1,gpop_old(nact,ilevel,icell),atom%n(ilevel,icell)
    ! 							end do !over ilevel
    ! 							do kr=1, atom%Nline
    !
    ! 								dN3 = abs(1.0 - Tex_old(nact, kr, icell) / ( atom%lines(kr)%Tex(icell) + tiny_dp ) )
    ! 								!dN3 = abs(atom%lines(kr)%Tex(icell) - Tex_old(nact, kr, icell)) / ( Tex_old(nact, kr, icell) + tiny_dp )
    ! 								dN2 = max(dN3, dN2)
    ! 								!!write(*,*) "line", icell, T(icell), Tex_old(nact, kr, icell),atom%lines(kr)%Tex(icell), dN2, dN3
    ! 								!dTM(nact) = max(dTM(nact), dN3)
    ! 								if (dN3 >= dTM(nact)) then
    ! 									dTM(nact) = dN3
    ! 									Tex_ref(nact) = atom%lines(kr)%Tex(icell)
    ! 									icell_max = icell
    ! 								endif
    ! 							enddo
    !
    ! 							do kr=1, atom%Ncont
    ! 								dN3 = abs(1.0 - Tex_old(nact, kr+atom%Nline, icell) / ( atom%continua(kr)%Tex(icell) + tiny_dp ))
    ! 								!dN3 = abs(atom%continua(kr)%Tex(icell) - Tex_old(nact, kr+atom%Nline, icell)) / ( Tex_old(nact, kr+atom%Nline, icell) + tiny_dp )
    ! 								dN2 = max(dN3, dN2)
    ! 								!!write(*,*) "cont", kr, " icell=",icell, " T=", T(icell), " Told=",Tex_old(nact, kr+atom%Nline, icell)," Tex=",atom%continua(kr)%Tex(icell), dN2, dN3
    ! 								!dTM(nact) = max(dTM(nact), dN3)
    ! 								if (dN3 >= dTM(nact)) then
    ! 									dTM(nact) = dN3
    ! 									Tion_ref(nact) = atom%continua(kr)%Tex(icell)
    ! 									icell_max_2 = icell
    ! 								endif
    ! 							enddo
    ! 							atom => NULL()
    ! 						end do !over atoms
    ! 						!compare for all atoms and all cells
    ! 						diff = max(diff, dN) ! pops
    ! ! 						diff = max(diff, dN2) ! Tex
    !
    ! 						dN1 = abs(1d0 - maxval(Jold(:,icell)/(tiny_dp + Jnew(:,icell))))
    ! 						!dN1 = maxval(abs(Jold(:,icell)-Jnew(:,icell))/(1d-30 + Jold(:,icell)))
    ! 						if (dN1 > dJ) then
    ! 							dJ = dN1
    ! 							imax = locate(abs(1d0 - Jold(:,icell)/(tiny_dp + Jnew(:,icell))), dJ)
    ! 							!imax = locate(abs(Jold(:,icell)-Jnew(:,icell))/(tiny_dp + Jold(:,icell)),dJ)
    ! 							lambda_max = lambda(imax)
    ! 						endif
    ! 						!replace old value by new
    ! 						Jold(:,icell) = Jnew(:,icell)
    ! 						Jnu_cont(:,icell) = Jnew_cont(:,icell)
    !
    ! 						lcell_converged(icell) = (real(diff) < precision) !(real(diff) < dpops_max_error)
    !
    ! 						!Re init for next iteration if any
    ! 						do nact=1, NactiveAtoms
    ! 							atom => ActiveAtoms(nact)%ptr_atom
    ! 							!!gpop_old(nact, 1:atom%Nlevel,icell) = atom%n(:,icell)
    ! 							atom%n(:,icell) = n_new(nact,1:atom%Nlevel,icell)
    ! 							do kr=1,atom%Nline
    ! 								Tex_old(nact, kr, icell) = atom%lines(kr)%Tex(icell)
    ! 							enddo
    ! 							do kr=1, atom%Ncont
    ! 								Tex_old(nact, kr+Atom%Nline,icell) = atom%continua(kr)%Tex(icell)
    ! 							enddo
    ! 							atom => NULL()
    !              				!!Recompute Profiles if needed here
    ! 						end do
    ! 						call NLTE_bound_free(icell)
    ! 						!because of opac nlte changed
    ! 						call interp_continuum_local(icell, chi0_bb(:,icell), eta0_bb(:,icell))
    ! 						!end init
    !
    ! 					end if
    ! 				end do cell_loop2 !icell
    !
    ! 				write(*,'(" -> "(1I10)" sub-iterations")') maxval(max_n_iter_loc)
    ! 				write(*,'(" -> icell_max1 #"(1I6)," icell_max2 #"(1I6))') icell_max, icell_max_2
    ! 				write(*,'(" -> dJ="(1ES14.5E3)" @"(1F14.4)" nm")') dJ, lambda_max !at the end of the loop over n_cells
    ! 				write(*,*) " ------------------------------------------------ "
    ! 				do nact=1,NactiveAtoms
    ! 					write(*,'("             Atom "(1A2))') ActiveAtoms(nact)%ptr_atom%ID
    ! 					write(*,'("   >>> dpop="(1ES17.8E3))') dM(nact)
    ! 					write(*,'("   >>>   dT="(1ES17.8E3))') dTM(nact)
    ! 					write(*,'("   >>> Te(icell_max2)="(1F14.4)" K", " Tion="(1F14.4)" K")') T(icell_max_2), Tion_ref(nact)
    ! 					write(*,'("   >>> Te(icell_max1)="(1F14.4)" K", " Texi="(1F14.4)" K")') T(icell_max), Tex_ref(nact)
    ! 					!if (Tion_ref(nact) /= 0.0)
    ! 					!if (Tex_ref(nact) /= 0.0)
    ! 					write(*,*) " ------------------------------------------------ "
    ! 				enddo
    ! 				write(*,'(" <<->> diff="(1ES17.8E3)," old="(1ES17.8E3))') diff, diff_old !at the end of the loop over n_cells
    ! 	        	write(*,"('Unconverged cells #'(1I5), ' fraction :'(1F12.3)' %')") size(pack(lcell_converged,mask=lcell_converged.eqv..false.)), 100.*real(size(pack(lcell_converged,mask=lcell_converged.eqv..false.)))/real(n_cells)
    ! 				write(*,*) " *************************************************************** "
    ! 				diff_old = diff
    ! 				!Not used if the next is not commented out
    ! ! 				lconverged = (real(diff) < dpops_max_error) !global convergence for all iterations
    !
    ! 				if (real(diff) < precision) then
    !            			if (lprevious_converged) then
    !             	  		lconverged = .true.
    !            			else
    !             	  		lprevious_converged = .true.
    !           	    	endif
    !         		else !continue to iterate even if n_rayons max is reached ?
    !            			lprevious_converged = .false.
    !            			if (.not.lfixed_rays) then
    !               			n_rayons = n_rayons * 2
    !               			write(*,*) ' -- Increasing number of rays :', n_rayons
    !              			if (n_rayons > n_rayons_max) then
    !               				if (n_iter >= maxIter) then
    !              		 			write(*,*) "Warning : not enough rays to converge !!"
    !                  				lconverged = .true.
    !               				end if
    !               			end if
    !           	   		end if
    !         		end if
    !
    ! 			!Not optimal, but fast relatively
    ! 			!must be parra
    ! 				if (iterate_ne .and. (mod(n_iter,n_iterate_ne)==0))  then
    ! 				write(*,*) "Recompute lte opacities"
    ! 				write(*,*) " not yet"
    ! 					stop
    !
    ! 				end if
    !
    !
    ! 			end do !while
    ! 			write(*,*) "step: ", etape, "Threshold: ", precision!dpops_max_error
    !
    ! 		end do !over etapes
    !
    ! ! -------------------------------- CLEANING ------------------------------------------ !
    !
    ! 		!Always written in nlte
    ! 		!if (lelectron_scattering) then
    !   		open(unit=20, file=Jnu_File_ascii, status="unknown")
    !   		write(20,*) n_cells, Nlambda_cont
    !   		do icell=1, n_cells
    !   			do la=1, Nlambda_cont
    !     			write(20,'(1F12.5,5E20.7E3)') lambda_cont(la), Jnu_cont(la,icell), 0.0, thomson(icell)/(chi_c(la,icell)+chi_c_nlte(la,icell)), 0.0, 0.0
    !    			enddo
    !   		enddo
    !   		close(20)
    !   		!endif
    !
    ! 		if (allocated(threeKminusJ)) then
    !
    !   			open(unit=20, file="anis_ascii.txt", status="unknown")
    !   			write(20,*) n_cells, Nlambda
    !   			do icell=1, n_cells
    !   				do la=1, Nlambda
    !     				write(20,'(1F12.5,5E20.7E3)') lambda(la), 0.5*threeKminusJ(la,icell)/Jnew(la,icell), 0.0, 0.0, 0.0, 0.0
    !    				enddo
    !   			enddo
    !   			close(20)
    !
    ! 		endif
    !
    ! 		deallocate(dM, dTM, Tex_ref, Tion_ref)
    ! 		if (allocated(Jnew)) deallocate(Jnew)
    ! 		if (allocated(Jnew_cont)) deallocate(Jnew_cont)
    ! 		if (allocated(Jold)) deallocate(Jold)
    ! 		if (allocated(n_new)) deallocate(n_new)
    !
    ! 		close(unit=unit_invfile)
    ! 		close(unit=unit_profiles)
!     return
!   end subroutine NLTEloop
  ! ------------------------------------------------------------------------------------ !

 
!   	subroutine integrate_i_icell(id,icell_in,x,y,z,u,v,w,iray,labs, I, Ic)
! 	! ------------------------------------------------------------------------------- !
! 	!
! 	! ------------------------------------------------------------------------------- !
!
! 		integer, intent(in) :: id, icell_in, iray
! 		real(kind=dp), intent(in) :: u,v,w
! 		real(kind=dp), intent(in) :: x,y,z
! 		logical, intent(in) :: labs
! 		real(kind=dp) :: x0, y0, z0, x1, y1, z1, l, l_contrib, l_void_before
! 		real(kind=dp), dimension(Nlambda, n_cells), intent(out) :: I
! 		real(kind=dp), dimension(Nlambda_cont, n_cells), intent(out) :: Ic
! 		real(kind=dp), dimension(Nlambda) :: Snu, tau, dtau
! 		real(kind=dp), dimension(Nlambda_cont) :: Snu_c, dtau_c, tau_c
! 		integer :: nbr_cell, icell, next_cell, previous_cell, icell_star, i_star, la, icell_p
! 		logical :: lcellule_non_vide, lsubtract_avg, lintersect_stars
!
! 		x1=x;y1=y;z1=z
! 		x0=x;y0=y;z0=z
! 		next_cell = icell_in
! 		nbr_cell = 0
!
! 		tau(:) = 0.0_dp
! 		tau_c(:) = 0.0_dp
!
! 		I(:,:) = 0d0
! 		Ic(:,:) = 0d0
! 		icell_p = icell_in
!
!   ! -------------------------------------------------------------- !
!   !*** propagation dans la grille ***!
!   ! -------------------------------------------------------------- !
!   ! Will the ray intersect a star
! 		call intersect_stars(x,y,z, u,v,w, lintersect_stars, i_star, icell_star)
!
!   ! Boucle infinie sur les cellules
! 		infinie : do ! Boucle infinie
!     ! Indice de la cellule
! 			icell = next_cell
! 			x0=x1 ; y0=y1 ; z0=z1
!     !write(*,*) "Boucle infinie, icell=", icell
!
! 			if (icell <= n_cells) then
! 				lcellule_non_vide = (icompute_atomRT(icell) > 0)
! 				if (icompute_atomRT(icell) < 0) return !-1 if dark
! 			else
! 				lcellule_non_vide=.false.
! 			endif
!
!     ! Test sortie ! "The ray has reach the end of the grid"
!
! 			if (test_exit_grid(icell, x0, y0, z0)) return
!
! 			if (lintersect_stars) then
! 				if (icell == icell_star) then
! 					!can be done better
!       				Icont(:,iray,id) =  Icont(:,iray,id) + exp(-tau_c) * Istar_cont(:,i_star) * local_stellar_brigthness(Nlambda_cont,lambda_cont,i_star, icell_prev,x0, y0, z0, u,v,w)
!					Itot(:,iray,id) =  Itot(:,iray,id) + exp(-tau) * Istar_tot(:,i_star) * local_stellar_brigthness(Nlambda,lambda,i_star, icell_prev, x0, y0, z0, u,v,w)
!        				return
!       			end if
!    			 endif
!
! 			nbr_cell = nbr_cell + 1
!
!     ! Calcul longeur de vol et profondeur optique dans la cellule
! 			previous_cell = 0 ! unused, just for Voronoi
! 			call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell,l, l_contrib, l_void_before)
!
!     !count opacity only if the cell is filled, else go to next cell
! 			if (lcellule_non_vide) then
! 				lsubtract_avg = ((nbr_cell == 1).and.labs) !not used yet
!      ! opacities in m^-1
!
! 				l_contrib = l_contrib * AU_to_m !l_contrib in m
!
! 				if ((nbr_cell == 1).and.labs) then
! 					ds(iray,id) = l_contrib
! 				endif
!
! 				!total bound-bound + bound-free + background opacities lte + nlte
! 				chi(:,id) = chi0_bb(:,icell)
! 				eta(:,id) = eta0_bb(:,icell)
! 				!includes a loop over all bound-bound, passive and active
! 				call opacity_atom_loc(id,icell,iray,x0,y0,z0,x1,y1,z1,u,v,w,l,( (nbr_cell==1).and.labs ) )
!
! 				dtau(:)   = l_contrib * chi(:,id)
!
! 				if (lelectron_scattering) then
! 					Snu = ( eta(:,id) + eta_es(:,icell) ) / ( chi(:,id) + tiny_dp )
! 					Snu_c = eta_c(:,icell) + thomson(icell) * Jnu_cont(:,icell)
! 				else
! 					Snu = eta(:,id) / ( chi(:,id) + tiny_dp )
! 					Snu_c = eta_c(:,icell)
! 				endif
!
! 				if (Nactiveatoms > 0) then
! 					Snu_c = ( Snu_c + eta_c_nlte(:,icell) ) / ( chi_c(:,icell) + chi_c_nlte(:,icell) + tiny_dp)
! 					dtau_c(:) = l_contrib * (chi_c(:,icell) + chi_c_nlte(:,icell))
! 				else
! 					Snu_c = Snu_c / (chi_c(:,icell) + tiny_dp)
! 					dtau_c(:) = l_contrib * chi_c(:,icell)
! 				endif
!
!
! 				I(:,icell) = I(:,icell_p) + exp(-tau(:)) * (1.0_dp - exp(-dtau(:))) * Snu(:)
! 				Ic(:,icell) = Ic(:,icell_p) + exp(-tau_c(:)) * (1.0_dp - exp(-dtau_c(:))) * Snu_c(:)
! 				icell_p = icell
!
! 				tau = tau + dtau
! 				tau_c = tau_c + dtau_c
!
! 			end if  ! lcellule_non_vide
! 		end do infinie
!
! 	return
! 	end subroutine integrate_i_icell
!
!   	subroutine integ_ray_line_i_new(id,icell_in,x,y,z,u,v,w,iray,labs)
! 	! ------------------------------------------------------------------------------- !
! 	!
! 	! ------------------------------------------------------------------------------- !
!
! 		integer, intent(in) :: id, icell_in, iray
! 		real(kind=dp), intent(in) :: u,v,w
! 		real(kind=dp), intent(in) :: x,y,z
! 		logical, intent(in) :: labs
! 		real(kind=dp) :: x0, y0, z0, x1, y1, z1, l, l_contrib, l_void_before, edt, et
! 		real(kind=dp), dimension(Nlambda) :: tau
! 		real(kind=dp) :: Snu, dtau, Snu_c, dtau_c
! 		real(kind=dp), dimension(Nlambda_cont) :: tau_c
! 		integer :: nbr_cell, icell, next_cell, previous_cell, icell_star, i_star, la
! 		logical :: lcellule_non_vide, lsubtract_avg, lintersect_stars
!
! 		x1=x;y1=y;z1=z
! 		x0=x;y0=y;z0=z
! 		next_cell = icell_in
! 		nbr_cell = 0
!
! 		tau(:) = 0.0_dp
! 		tau_c(:) = 0.0_dp
!
! 		Itot(:,iray,id) = 0d0
! 		Icont(:,iray,id) = 0d0
!
!
! !!write(*,*) "id=",id
! !!write(*,*) "****"
!   ! -------------------------------------------------------------- !
!   !*** propagation dans la grille ***!
!   ! -------------------------------------------------------------- !
!   ! Will the ray intersect a star
! 		call intersect_stars(x,y,z, u,v,w, lintersect_stars, i_star, icell_star)
!
!   ! Boucle infinie sur les cellules
! 		infinie : do ! Boucle infinie
!     ! Indice de la cellule
! 			icell = next_cell
! 			x0=x1 ; y0=y1 ; z0=z1
!     !write(*,*) "Boucle infinie, icell=", icell
!
! 			if (icell <= n_cells) then
! 				lcellule_non_vide = (icompute_atomRT(icell) > 0)
! 				if (icompute_atomRT(icell) < 0) return !-1 if dark
! 			else
! 				lcellule_non_vide=.false.
! 			endif
!
!     ! Test sortie ! "The ray has reach the end of the grid"
!
! 			if (test_exit_grid(icell, x0, y0, z0)) return
!
! 			if (lintersect_stars) then
! 				if (icell == icell_star) then
!       				Icont(:,iray,id) =  Icont(:,iray,id) + exp(-tau_c) * Istar_cont(:,i_star) * local_stellar_brigthness(Nlambda_cont,lambda_cont,i_star, icell_prev,x0, y0, z0, u,v,w)
!					Itot(:,iray,id) =  Itot(:,iray,id) + exp(-tau) * Istar_tot(:,i_star) * local_stellar_brigthness(Nlambda,lambda,i_star, icell_prev, x0, y0, z0, u,v,w)
!        				return
!       			end if
!    			 endif
!
! 			nbr_cell = nbr_cell + 1
!
!     ! Calcul longeur de vol et profondeur optique dans la cellule
! 			previous_cell = 0 ! unused, just for Voronoi
! 			call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell,l, l_contrib, l_void_before)
!
!     !count opacity only if the cell is filled, else go to next cell
! 			if (lcellule_non_vide) then
! 				lsubtract_avg = ((nbr_cell == 1).and.labs) !not used yet same as iterate?
!      ! opacities in m^-1
!
! 				l_contrib = l_contrib * AU_to_m !l_contrib in m
!
! 				!total bound-bound + bound-free + background opacities lte + nlte
! 				chi(:,id) = chi0_bb(:,icell)
! 				eta(:,id) = eta0_bb(:,icell)
! 				!rename it chi0_bckgr etc
!
! 				!includes a loop over all bound-bound, passive and active
! 				call opacity_atom_loc(id,icell,iray,x0,y0,z0,x1,y1,z1,u,v,w,l,( (nbr_cell==1).and.labs ) )
!
! 				do la=1, Nlambda
! 					dtau = l_contrib * chi(la,id)
!
! 					if ((nbr_cell == 1).and.labs) then
! 						if (lmali_scheme) then
! 							psi(la,iray,id) = ( 1.0_dp - exp( -l*AU_to_m*chi(la,id) ) ) / chi(la,id)
! 						else
! 							ds(iray,id) = l_contrib
! 						endif
! 					endif
!
!
! 					if (lelectron_scattering) then
! 						Snu = ( eta(la,id) + eta_es(la,icell) ) / ( chi(la,id) + tiny_dp )
! 					else
! 						Snu = eta(la,id) / ( chi(la,id) + tiny_dp )
! 					endif
!
!
! 					Itot(la,iray,id) = Itot(la,iray,id) + ( exp(-tau(la)) - exp(-(tau(la)+dtau)) ) * Snu
! 					tau(la) = tau(la) + dtau !for next cell
! 				enddo
!
! 				do la=1, Nlambda_cont
! 					if (lelectron_scattering) then
! 						Snu_c = eta_c(la,icell) + thomson(icell) * Jnu_cont(la,icell)
! 					else
! 						Snu_c = eta_c(la,icell)
! 					endif
!
! 					if (Nactiveatoms > 0) then
! 						Snu_c = ( Snu_c + eta_c_nlte(la,icell) ) / ( chi_c(la,icell) + chi_c_nlte(la,icell) + tiny_dp)
! 						dtau_c = l_contrib * (chi_c(la,icell) + chi_c_nlte(la,icell))
! 					else
! 						Snu_c = Snu_c / (chi_c(la,icell) + tiny_dp)
! 						dtau_c = l_contrib * chi_c(la,icell)
! 					endif
!
! 					Icont(la,iray,id) = Icont(la,iray,id) + ( exp(-tau_c(la)) - exp(-(tau_c(la) + dtau_c)) ) * Snu_c
! 					tau_c(la) = tau_c(la) + dtau_c
! 				enddo
!
!
! 			end if  ! lcellule_non_vide
! 		end do infinie
!
! 	return
! 	end subroutine integ_ray_line_i_new
! function local_stellar_brigthness(N,lambda,i_star,icell_prev,x,y,z,u,v,w)
!    ! ---------------------------------------------------------------!
!    !
!    ! -------------------------------------------------------------- !
!    use atmos_type, only : thetai, thetao
!    integer, intent(in) :: N, i_star, icell_prev
!    real(kind=dp), dimension(N), intent(in) :: lambda
!    real(kind=dp), intent(in) :: u, v, w, x, y, z
!    real(kind=dp), dimension(N) :: local_stellar_brigthness

!    real(kind=dp) :: Tchoc, vaccr, vmod2, rr, enthalp
!    real(kind=dp) :: mu, ulimb, LimbDarkening, sign_z
!    integer :: ns,la
!    logical :: lintersect!=.false.! does not work here ?

!    if (etoile(i_star)%T <= 1e-6) then !even with spots
!       local_stellar_brigthness(:) = 0.0_dp !look at init_stellar_disk
!       return !no radiation from the starr
!    endif

!    local_stellar_brigthness = 1.0_dp

!    !cos(theta) = dot(r,n)/module(r)/module(n)
!    if (llimb_darkening) then
!       call ERROR("option for reading limb darkening not implemented")
!       mu = abs(x*u + y*v + z*w)/sqrt(x**2+y**2+z**2) !n=(u,v,w) is normalised
!       if (real(mu)>1d0) then !to avoid perecision error
!          write(*,*) "mu=",mu, x, y, z, u, v, w
!          call Error(" mu limb > 1!")
!       end if
!    else
!       LimbDarkening = 1.0_dp
!    end if

   !->oldie
   !    call intersect_spots(i_star,u,v,w,x,y,z, ns,lintersect)
   !    !avoid error with infinity for small lambda
   !    if (lintersect) then
   !    		!Means that Ispot = Bp(Tspot) = gamma * Iphot  = Ispot
   !    		!gamma is initialized to one here.
   !    		!The +1 (i.e., the gamma = gamma + ...) means that Istar = Iphot + Ispot = Iphot * (1 + gamma)
   ! 		local_stellar_brigthness(:) = local_stellar_brigthness(:) + (exp(hc_k/max(lambda,10.0)/etoile(i_star)%T)-1)/(exp(hc_k/max(lambda,10.0)/etoile(i_star)%SurfB(ns)%T)-1)
   !      !so that I_spot = Bplanck(Tspot) = Bp(Tstar) * gamma = Bp(Tstar)*B_spot/B_star
   !      	!Lambda independent spots, Ts = 2*Tphot means Fspot = 2 * Fphot
   !  		!gamma = gamma + (etoile(i_star)%SurfB(ns)%T - etoile(i_star)%T) / etoile(i_star)%T
   !    end if

   !better to store a map(1:n_cells) with all Tchoc
   !and if map(icell_prev) > 0 -> choc

!    lintersect = .false.
!    if ((laccretion_shock).and.(icell_prev<=n_cells)) then
!       if (icompute_atomRT(icell_prev) > 0) then
!          rr = sqrt( x*x + y*y + z*z )
!          enthalp = 2.5 * 1d3 * kb * T(icell_prev) / wght_per_H / masseH

!          if (lvoronoi) then
!             vaccr = Voronoi(icell_prev)%vxyz(1)*x/rr + Voronoi(icell_prev)%vxyz(2)*y/rr + Voronoi(icell_prev)%vxyz(3) * z/rr
!             vmod2 = sum( Voronoi(icell_prev)%vxyz(:)**2 )
!          else
!             if (lmagnetoaccr) then
!                if (l3D) then
!                   sign_z = 1.0
!                else
!                   sign_z = sign(1.0, z)
!                endif
!                vaccr = vr(icell_prev) * sqrt(1.0 - (z/rr)**2) + sign_z * v_z(icell_prev) * z/rr
!                vmod2 = vr(icell_prev)**2+v_z(icell_prev)**2+vphi(icell_prev)**2
!             else
!                vaccr = vr(icell_prev)
!                vmod2 = vr(icell_prev)**2+vtheta(icell_prev)**2+vphi(icell_prev)**2

!             endif
!          endif

!          ! 				if (vaccr < 0.0_dp) then
!          if ( (vaccr < 0.0_dp) .and. ( (abs(z)/rr >= cos(thetai)).and.(abs(z)/rr <= cos(thetao)) ) ) then
!             if (Taccretion>0) then
!                Tchoc = Taccretion
!                lintersect = .true.
!             else
!                Tchoc = (1d-3 * masseH * wght_per_H * nHtot(icell_prev)/sigma * abs(vaccr) * (0.5 * vmod2 + enthalp))**0.25
!                lintersect = (Tchoc > etoile(i_star)%T)
!             endif
!             ! 					lintersect = (Tchoc > etoile(i_star)%T)
!          endif

!       endif !icompute_atomRT
!       if (lintersect) then
!          local_stellar_brigthness(:) = local_stellar_brigthness(:) + &
!               (exp(hc_k/max(lambda,10.0)/etoile(i_star)%T)-1)/(exp(hc_k/max(lambda,10.0)/Tchoc)-1)
!          !Assuming BB shock
!       endif
!    endif !laccretion_shock

!    local_stellar_brigthness(:) = LimbDarkening * local_stellar_brigthness(:)

!    return
!  end function local_stellar_brigthness

   ! subroutine integ_ray_sobolev(id,icell_in,x,y,z,u,v,w,iray,labs)
   !    use opacity, only : opacity_sobolev_loc
   !    ! ------------------------------------------------------------------------------- !
   !    ! Special version for the Sobolev approximation in non-LTE loop
   !    ! tau includes only line processes with the sobolev optical length
   !    ! stellar photons unnafected by the continuum
   !    ! the emission from the cell icell_in is not included in Itot
   !    ! separate Itot and Istar_loc ?  
   !    ! ------------------------------------------------------------------------------- !
   
   !       integer, intent(in) :: id, icell_in, iray
   !       real(kind=dp), intent(in) :: u,v,w
   !       real(kind=dp), intent(in) :: x,y,z
   !       logical, intent(in) :: labs
   !       real(kind=dp) :: x0, y0, z0, x1, y1, z1, l, l_contrib, l_void_before
   !       real(kind=dp), dimension(Nlambda) :: Snu, tau, dtau
   !       real(kind=dp), dimension(Nlambda_cont) :: tau_c
   !       integer :: nbr_cell, icell, next_cell, previous_cell, icell_star, i_star, la, icell_prev
   !       logical :: lcellule_non_vide, lsubtract_avg, lintersect_stars
   
   !       x1=x;y1=y;z1=z
   !       x0=x;y0=y;z0=z
   !       next_cell = icell_in
   !       nbr_cell = 0
   !       icell_prev = icell_in
   
   !       tau_c(:) = 0.0 !no used
   !       tau(:) = 0.0_dp   
   !       Itot(:,iray,id) = 0.0_dp
   !       Icont(:,iray,id) = 0.0_dp
   
   !       Istar_loc(:,id) = 0.0_dp
   !       if (laccretion_shock) Ishock(:,id) = 0.0_dp
   
   
   !       ! Will the ray intersect a star
   !       call intersect_stars(x,y,z, u,v,w, lintersect_stars, i_star, icell_star)
   !       ! Boucle infinie sur les cellules (we go over the grid.)
   !       infinie : do ! Boucle infinie
   !       ! Indice de la cellule
   !          icell = next_cell
   !          x0=x1 ; y0=y1 ; z0=z1
   
   !          lcellule_non_vide = (icell <= n_cells)
   
   !          ! Test sortie ! "The ray has reach the end of the grid"
   !          if (test_exit_grid(icell, x0, y0, z0)) return
   
   !          if (lintersect_stars) then !"will interesct"
   !             if (icell == icell_star) then!"has intersected"
   !                !here the stellar radiation is unaffected by continua and absorbed only in lines
   !                call local_stellar_radiation(id,iray,tau,tau_c,i_star,icell_prev,x0,y0,z0,u,v,w)
   !                return
   !             end if
   !          endif
   !          !With the Voronoi grid, somme cells can have a negative index
   !          !therefore we need to test_exit_grid before using icompute_atom_rt
   !          if (icell <= n_cells) then
   !             lcellule_non_vide = (icompute_atomRT(icell) > 0)
   !             if (icompute_atomRT(icell) < 0) return
   !          endif
   
   !          nbr_cell = nbr_cell + 1
   
   !          ! Calcul longeur de vol et profondeur optique dans la cellule
   !          previous_cell = 0 ! unused, just for Voronoi
   !          call cross_cell(x0,y0,z0, u,v,w,  icell, previous_cell, x1,y1,z1, next_cell,l, l_contrib, l_void_before)
   
   !          !count opacity only if the cell is filled, else go to next cell
   !          if (lcellule_non_vide) then
   !             lsubtract_avg = ((nbr_cell == 1).and.labs) !not used yet same as iterate?
   !             ! opacities in m^-1, l_contrib in au
   
   !             chi(:,id) = 0.0_dp
   !             eta(:,id) = 0.0_dp
   
   !             !includes a loop over all bound-bound, passive and active
   !             call opacity_sobolev_loc(id,icell,iray,x0,y0,z0,x1,y1,z1,u,v,w,l_void_before,l_contrib,(nbr_cell==1))
   !             !chi in s^-1, dtau in m/s
   !             dtau(:) = l_contrib * chi(:,id) * AU_to_m
   
   !             if ((nbr_cell == 1).and.labs) then
   !                ds(iray,id) = l_contrib * AU_to_m
   !                gradv(iray,id) = abs(v_proj(icell,x1,y1,z1,u,v,w)-vlabs(iray,id))
   !             endif
   !             !works because there is only lines and only 1 atom
   !             dtau(:) = dtau(:) / mean_grad_v(icell)!-> m/s * s/m
   
   !             !must be constant over the line and zero otherwise
   !             Snu = eta(:,id) / ( chi(:,id) + tiny_dp )
   
   !             if (.not.lno_radiative_coupling) then
   !                if (nbr_cell>1) then
   !                   Itot(:,iray,id) = Itot(:,iray,id) + exp(-tau) * (1.0_dp - exp(-dtau)) * Snu
   !                endif
   !             endif
   !             !otherwise Itot contains only the star contribution
   !             tau(:) = tau(:) + dtau(:) !for next cell
   
   !          end if  ! lcellule_non_vide
   
   !          icell_prev = icell 
   !          !duplicate with previous_cell, but this avoid problem with Voronoi grid here
   
   !       end do infinie
   
   !       return
   !    end subroutine integ_ray_sobolev
! subroutine local_stellar_radiation(id,iray,tau,tau_c,i_star,icell_prev,x,y,z,u,v,w)
!    ! ---------------------------------------------------------------!
!    ! routine to manage the radiation of the stellar boundary
!    ! -------------------------------------------------------------- !
!    use atmos_type, only : thetai, thetao
!       integer, intent(in) :: i_star, icell_prev, id, iray
!       real(kind=dp), dimension(:), intent(in) :: tau, tau_c
!       real(kind=dp), intent(in) :: u, v, w, x, y, z
!       ! real(kind=dp), parameter :: prec = 1d-5
!       real(kind=dp) :: Tchoc, vaccr, vmod2, rr, enthalp
!       real(kind=dp) :: mu, ulimb, LimbDarkening, sign_z
!       integer :: ns,la
!       logical :: lintersect

!       if (etoile(i_star)%T <= 1e-6) then !even with spots
!          return !no radiation from the star
!       endif


!       !cos(theta) = dot(r,n)/module(r)/module(n)
!       if (llimb_darkening) then
!          call ERROR("option for reading limb darkening not implemented")
!          mu = abs(x*u + y*v + z*w)/sqrt(x**2+y**2+z**2) !n=(u,v,w) is normalised
!          if (real(mu)>1d0) then !to avoid perecision error
!             write(*,*) "mu=",mu, x, y, z, u, v, w
!             call Error(" mu limb > 1!")
!          end if
!       else
!          LimbDarkening = 1.0_dp
!       end if

!       Istar_loc(:,id) = Limbdarkening * exp(-tau(:)) * Istar_tot(:,i_star)

!       if (is_inshock(id, iray, i_star, icell_prev, x, y, z, Tchoc)) then
!          Ishock(:,id) = LimbDarkening * exp(-tau(:)) * Bpnu(Tchoc,lambda)
!          Itot(:,iray,id) = Itot(:,iray,id) + Ishock(:,id) + Istar_loc(:,id)
!          Icont(:,iray,id) = Icont(:,iray,id) + LimbDarkening * exp(-tau_c(:)) *&
!             (Bpnu(Tchoc,lambda_cont) + Istar_cont(:,i_star)) 

!          return
!       endif

!       ! lintersect = .false.
!       ! if ((laccretion_shock).and.(icell_prev<=n_cells)) then
!       !    if (icompute_atomRT(icell_prev) > 0) then
!       !       rr = sqrt( x*x + y*y + z*z)
!       !       !specific enthalpy of the gas
!       !       enthalp = 2.5 * 1d3 * kb * T(icell_prev) / wght_per_H / masseH

!       !       !vaccr is vr, the spherical r velocity component
!       !       if (lvoronoi) then !always 3d
!       !          vaccr = Voronoi(icell_prev)%vxyz(1)*x/rr + Voronoi(icell_prev)%vxyz(2)*y/rr + Voronoi(icell_prev)%vxyz(3) * z/rr
!       !          vmod2 = sum( Voronoi(icell_prev)%vxyz(:)**2 )
!       !       else
!       !          if (lmagnetoaccr) then
!       !             if (l3D) then !needed here if not 2.5d
!       !                sign_z = 1.0
!       !             else
!       !                sign_z = sign(1.0, z)
!       !             endif
!       !             vaccr = vr(icell_prev) * sqrt(1.0 - (z/rr)**2) + sign_z * v_z(icell_prev) * z/rr
!       !             vmod2 = vr(icell_prev)**2+v_z(icell_prev)**2+vphi(icell_prev)**2
!       !          else !spherical vector here
!       !             vaccr = vr(icell_prev) !always negative for accretion
!       !             vmod2 = vr(icell_prev)**2+vtheta(icell_prev)**2+vphi(icell_prev)**2
!       !          endif
!       !       endif

!       !       !test with thetao and thetai to restrain the shock area a "shock" inside a shock
!       !       !-> does not work
!       !       ! if ( (vaccr < 0.0_dp) .and. ( (abs(z)/rr >= cos(thetai)).and.(abs(z)/rr <= cos(thetao)) ) ) then
!       !       if (vaccr < 0.0_dp) then
!       !          !Even if fixed choc temperature, check that the column contributes to the accretion by computing
!       !          !Tchoc from kinetic energy and be sure that it is larger than, say, 1000 K.
!       !          Tchoc = (1d-3 * masseH * wght_per_H * nHtot(icell_prev)/sigma * abs(vaccr) * &
!       !             (0.5 * vmod2 + enthalp))**0.25
!       !          lintersect = (Tchoc > 1000.0)
!       !          if (Taccretion>0) then !constant accretion shock value from file
!       !             Tchoc = Taccretion
!       !             ! lintersect = .true.
!       !          else! computed from mass flux and corrected by Taccretion factor!
!       !             Tchoc = abs(Taccretion) * Tchoc
!       !             ! Tchoc = abs(Taccretion) * (1d-3 * masseH * wght_per_H * nHtot(icell_prev)/sigma * abs(vaccr) * &
!       !             !    (0.5 * vmod2 + enthalp))**0.25
!       !             !recompute lintersect in that case to not include the thin accreting regions.
!       !             lintersect = (Tchoc > 1.0*etoile(i_star)%T) !depends on the local value
!       !          endif
!       !       endif

!       !    endif !icompute_atomRT
!       !    if (lintersect) then
!       !       Ishock(:,id) = LimbDarkening * exp(-tau(:)) * Bpnu(Tchoc,lambda)
!       !       Itot(:,iray,id) = Itot(:,iray,id) + Ishock(:,id) + Istar_loc(:,id)
!       !       Icont(:,iray,id) = Icont(:,iray,id) + LimbDarkening * exp(-tau_c(:)) *&
!       !          (Bpnu(Tchoc,lambda_cont) + Istar_cont(:,i_star)) 
!       !       return
!       !    endif
!       ! endif !laccretion_shock

!       Itot(:,iray,id) = Itot(:,iray,id) + Istar_loc(:,id)
!       Icont(:,iray,id) = Icont(:,iray,id) + LimbDarkening * exp(-tau_c(:)) * &
!          Istar_cont(:,i_star)

!       return
!    end subroutine local_stellar_radiation