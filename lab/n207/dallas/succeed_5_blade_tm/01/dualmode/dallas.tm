%% ============================================================
%% ============== TM CONFIGURATION  ===========================
%% ============================================================

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% %%%%%%%%%%%%%%  TRAFFIC MODEL LTE  %%%%%%%%%%%%%%%%%%%%%%%%%
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% Traffic Model description for LTE subscribers
%% Ericsson Global TM


{tm, [
    {name, lte},
    {tm_control, [
        {enable_traffic_during_startup, true},
        {initial_activations_per_sec, 400},
        %%{initial_activations_per_sec, 100},
        {sds_to_total_subs_ratio, 0.7},
        {sim_delays, true},
        {tm_latency, [
            {max_tm_latency, 2500},
            {min_tm_latency, 2000}
            ]},
        {max_random_delay, 0},
        {always_on, true}
        ]},
    {access_control, [
        {eutran, [
            {attach_detach, [
                {sau_based_rate, 0.6},
                {detach_cause_weight, [
                    {power_off, 70},
                    {silent, 0},
                    {normal, 30}
                    ]}
                ]},
            {an_release, [
                {timer, 43}
                ]}
            ]}
        ]},
    {session_control, [
        {eutran, [
            {session_creation, [
                {pdn_connection, [
                    {sau_based_rate, 60.0}
                    ]},
                {dedicated_bearer, [
                    {sau_based_rate, 0.0},
                    {number_range_list, [70,30]}
                    ]}
                ]},
            {session_modification, [
                {erab_modification, [
                    {sau_based_rate, 0}
                    ]},
                {hss_init_qos_update, [
                    {sau_based_rate, 0.0}
                    ]},
                {pgw_init_qos_update, [
                    {sau_based_rate, 0}
                    ]}
                ]},
            {session_deletion, [
                {pdn_connection, [
                    {sau_based_rate, 0.1}
                    ]},
                {dedicated_bearer, [
                    {sau_based_rate, 0.0},
                    {cause_weight, [
                        {nw_trigger, 100},
                        {an_trigger, 0}
                        ]},
                    {number_range_list, [70,30]}
                    ]}
                ]}
            ]}
        ]},
    {mobility_control, [
        {eutran, [
            {idle_mobility, [
                {intra_mme, [
                    {sau_based_rate, 1.3},
                    {per_type_weight, [
                        {normal, 1},
                        {combined, 0},
                        {combined_wi, 0}
                        ]}
                    ]},
                {inter_mme, [
                    {to_real_mme, [
                        {sau_based_rate, 0}
                        ]}
                    ]}
                ]},
            {s1_handover, [
                {intra_mme, [
                    {sau_based_rate, 1.3}
                    ]},
                {inter_mme, [
                    {sau_based_rate, 0}
                    ]}
                ]},
            {x2_handover, [
                {intra_mme, [
                    {sau_based_rate, 7.4}
                    ]}
                ]},
            {untrusted_wifi_handover, [
                {sau_based_rate, 0}
                ]},
            {inter_system_to_wcdma, [
                {sau_based_rate, 0}
                ]}
            ]}
        ]},
    {payload_control, [
        {eutran, [
            {sau_based_rate, 32}
            ]}
        ]},
    {trace_control, [
        {eutran, [
            {cell_traffic_trace, [
                {sau_based_rate, 1}
                ]}
            ]}
        ]},
    {charging_control, [
        {eutran, [
            {secondary_rat_data_usage_report, [
                {sau_based_rate, 0}
                ]}
            ]}
        ]}
]}.


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% %%%%%%%%%%%%%%  TRAFFIC MODEL 5G   %%%%%%%%%%%%%%%%%%%%%%%%%
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% Traffic Model description for 5G subscribers
%%

{tm, [
        {name, nr_multitm},
        {tm_control, [
                {enable_traffic_during_startup, true},
                {initial_activations_per_sec, 400},
		%%initial_activations_per_sec, 150},
                {sds_to_total_subs_ratio, 0.7},
                {sim_delays, true},
                {tm_latency, [
                        {max_tm_latency, 6000},
                        {min_tm_latency, 5000}
                ]},
                {max_random_delay, 0},
                {always_on, true},
                {initial_pdu_session_ratio, 0.992}
        ]},
        {access_control, [
                {nr, [
                        {registration_deregistration,[
                                {sau_based_rate, 0.7},
                                {initial_registration_mobile_identity_type_weight, [
                                        {suci, 30},
                                        {guti, 70}
                                ]},
                                {deregistration_cause_weight, [
                                        {power_off, 5},
                                        {normal, 95}
                                ]}
                        ]},
                        {an_release, [
                                {active_to_idle_timeout,39}
                        ]}
                ]}
        ]},
        {session_control, [
                {nr, [
                        {session_creation, [
                                {pdu_session, [
                                        {sau_based_rate, 0.01}
                                ]}
                        ]},
                        {session_modification, [
                                {smf_initial_modification, [
                                        {sau_based_rate, 0}
                                ]}
                        ]},
                        {session_deletion, [
                                {pdu_session, [
                                        {sau_based_rate, 0.01}
                                ]}
                        ]}
                ]}
        ]},
        {mobility_control, [
                {nr, [
                        {n2_handover, [
                                {per_type_rate, [
                                        {amf_change, false},
                                        {upf_change, false},
                                        {smf_change, false},
                                        {sau_based_rate, 0.65}
                                ]}
                        ]},
                        {xn_handover, [
                                {per_type_rate, [
                                        {amf_change, false},
                                        {upf_change, false},
                                        {smf_change, false},
                                        {sau_based_rate, 10.1}
                                ]}
                        ]},
                        {mobility_registration, [
                                {intra_amf, [
                                        {sau_based_rate, 1.8}
                                ]},
                                {inter_amf, [
                                        {sau_based_rate, 0}
                                ]}
                        ]}
                ]}
        ]},
        {payload_control, [
                {nr, [
                        {sau_based_rate, 31}
                ]}
        ]}
]}.

