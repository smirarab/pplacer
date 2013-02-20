open OUnit
open Test_util
open Ppatteries

module P = Lcfit.Pair
module T = Lcfit.Tripod

let m = {T.n00=1500.; T.n01=300.; T.n10=300.; T.n11=300.; T.r=1.; T.b=0.5;
         T.t=0.390296; T.rx=1.; T.bx=0.5}

let assert_approx_equal ?(epsilon=1e-2) expected actual =
  if not (approx_equal ~epsilon expected actual) then
    assert_failure (Printf.sprintf "%f != %f" actual expected)

let pair_tests = [
  "test_monotonic" >:: begin fun() ->
    assert_equal P.Increasing (P.monotonicity [(1.0, 2.0); (1.1, 3.0); (4.0, 6.0)]);
    assert_equal P.Decreasing (P.monotonicity [(1.0, 2.0); (1.1, 1.0); (1.4, -8.0)]);
    assert_equal P.Non_monotonic (P.monotonicity [(1.0, 1.0); (1.1, 3.0); (4.0, -8.0)]);
  end;
  "test_pair_fit" >:: begin fun() ->
    let points = [(0.1,-23753.3);
                  (0.2,-23701.5);
                  (0.5,-23648.7);
                  (1.0,-23677.8);]
    and init_model = {P.c=1100.0; P.m=800.0; P.r=2.0; P.b=0.5}
    (* t, actual_ll, fit_ll from c++ interface *)
    and exp_pts = [(0.04,-23804.9,-23798.2);
                   (0.08,-23768.0,-23766.9);
                   (0.12,-23740.3,-23740.8);
                   (0.16,-23718.7,-23719.2);
                   (0.20,-23701.5,-23701.5);
                   (0.24,-23687.8,-23687.1);
                   (0.28,-23676.8,-23675.7);
                   (0.32,-23668.1,-23666.7);
                   (0.36,-23661.3,-23659.9);
                   (0.40,-23656.1,-23654.9);
                   (0.44,-23652.2,-23651.5);
                   (0.48,-23649.6,-23649.3);
                   (0.52,-23648.1,-23648.4);
                   (0.56,-23647.4,-23648.3);
                   (0.60,-23647.5,-23649.1);
                   (0.64,-23648.4,-23650.5);
                   (0.68,-23649.9,-23652.4);
                   (0.72,-23652.0,-23654.8);
                   (0.76,-23654.5,-23657.5);
                   (0.80,-23657.5,-23660.5);
                   (0.84,-23660.9,-23663.8);
                   (0.88,-23664.7,-23667.2);
                   (0.92,-23668.8,-23670.6);
                   (0.96,-23673.2,-23674.2);]
    in
    let scaled = P.rescale (0.5, -23648.7) init_model in
    let fit = P.fit scaled (Array.of_list points) in
    let log_like = P.log_like fit in
    let f (t, actual, _) =
      let fit_ll = log_like t in
      Float.abs (fit_ll -. actual)
    in
    let err = List.enum exp_pts
      |> map f
      |> reduce (+.)
    in
    assert_bool (Printf.sprintf "Error out of range: %f" err) (err < 41.);
  end;
]

let tripod_tests = [
  "test_ll_matches_mathematica" >:: begin fun() ->
    let test_func (tx, c, l) =
      let actual = T.log_like m c tx in
      assert_approx_equal ~epsilon:1e-2 l actual
    in
    List.iter
      test_func
      (* (tx, c, log-likelihood) *)
      [(0.01, 0.1, -4371.24);
       (0.01, 0.2, -4370.45);
       (0.01, 0.3, -4371.41);
       (0.1, 0.1, -4390.43);
       (0.1, 0.2, -4389.98);
       (0.1, 0.3, -4390.53);
       (1.0, 0.1, -4574.57);
       (1.0, 0.2, -4575.06);
       (1.0, 0.3, -4574.47);
      ];
  end;
  "test_jacobian_matches_mathematica" >:: begin fun() ->
    (* tx, c, jacobian *)
    let data = [
      (0.01, 0.1, [|-1.46370919482;-2.29250329026;-2.44488253075;-2.51486367522;-307.142409213;-439.512154795;-104.660686471;-205.217032297|]);
      (0.01, 0.2, [|-1.46517311212;-2.36967270222;-2.36192885968;-2.51068727531;-309.943200566;-445.860652141;-106.91058354;-209.628595176|]);
      (0.01, 0.3, [|-1.46339453633;-2.45334127174;-2.28529674788;-2.51576444531;-306.544196266;-438.132218135;-104.171269993;-204.257392143|]);
      (0.1, 0.1, [|-1.49210087043;-2.29860423537;-2.43782395954;-2.43782395954;-312.871592946;-448.766389556;-131.752710474;-219.58785079|]);
      (0.1, 0.2, [|-1.49347726004;-2.36933821283;-2.36226087947;-2.43428889779;-315.510674459;-453.872283142;-133.770176404;-222.950294007|]);
      (0.1, 0.3, [|-1.49180500966;-2.44549728117;-2.29197572848;-2.43858610775;-312.307406821;-447.657588823;-131.314082186;-218.856803644|]);
      (1.0, 0.1, [|-1.69234781952;-2.33792947697;-2.39445579297;-2.05444783337;-288.661591377;-416.66874539;-242.86447543;-161.909650287|]);
      (1.0, 0.2, [|-1.69303124638;-2.36723302952;-2.36435561053;-2.05346701477;-289.982916415;-417.156469342;-242.814540389;-161.876360259|]);
      (1.0, 0.3, [|-1.69220085218;-2.39743613186;-2.33512107292;-2.05465896661;-288.377773824;-416.563035891;-242.874274741;-161.916183161|])
    ]
    and assert_same_jacobian (tx, c, expected) =
      let actual = T.jacobian m c tx in
      Array.iter2 assert_approx_equal expected actual
    in
    List.iter assert_same_jacobian data
  end;
  "test_fit_success" >:: begin fun() ->
    let to_fit = [|(0.350001, 0.460001, -700.233911883);
                   (0.310001, 0.140001, -721.128947905);
                   (0.280001, 0.600001, -697.193926396);
                   (0.320001, 0.020001, -793.03382342);
                   (0.330001, 0.260001, -706.334497659);
                   (0.180001, 0.400001, -694.312881641);
                   (0.170001, 0.170001, -708.884610045);
                   (0.270001, 0.090001, -730.369797453);
                   (0.140001, 0.050001, -750.584426125);
                   (0.380001, 0.070001, -777.020173121);
                   (0.250001, 0.120001, -719.268957126);
                   (0.220001, 0.790001, -702.183981614);
                   (0.170001, 0.330001, -695.897769298);
                   (0.160001, 0.660001, -698.511693664);
                   (0.020001, 0.190001, -733.643533379);
                   (0.360001, 0.400001, -702.732261827);
                   (0.210001, 0.500001, -694.35172057);
                   (0.270001, 0.200001, -706.058159612);
                   (0.240001, 0.390001, -694.333672064);
                   (0.370001, 0.120001, -744.396900924)|]
    and scaled = T.rescale (0.180001, 0.400001, -694.3129) m in
    let fit_model = T.fit scaled to_fit in
    let log_like = T.log_like fit_model in
    let err = to_fit
      |> Array.enum
      |> map (fun (c, tx, l) -> l -. (log_like c tx) |> abs_float)
      |> reduce (+.)
    in
    (* TODO: better fit test - this just checks for success. *)
    assert_bool (Printf.sprintf "Error out of range: %f" err) (err < 5.);
  end;
  "test_est_rx" >:: begin fun() ->
    let pt = (0.2,1.0,-1.69) in
    let res = T.est_rx m pt in
    assert_approx_equal 0.986757 res;
  end;
]

let suite = pair_tests @ tripod_tests