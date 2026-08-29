export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      approval_actions: {
        Row: {
          action: Database["public"]["Enums"]["approval_status"]
          action_at: string
          action_by: string
          amount_at_action: number | null
          approval_request_id: string
          comments: string | null
          id: string
        }
        Insert: {
          action: Database["public"]["Enums"]["approval_status"]
          action_at?: string
          action_by: string
          amount_at_action?: number | null
          approval_request_id: string
          comments?: string | null
          id?: string
        }
        Update: {
          action?: Database["public"]["Enums"]["approval_status"]
          action_at?: string
          action_by?: string
          amount_at_action?: number | null
          approval_request_id?: string
          comments?: string | null
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "approval_actions_action_by_fkey"
            columns: ["action_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_actions_approval_request_id_fkey"
            columns: ["approval_request_id"]
            isOneToOne: false
            referencedRelation: "approval_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_requests: {
        Row: {
          approval_level: string
          comp_earning_id: string
          completed_at: string | null
          due_at: string | null
          id: string
          notes: string | null
          requested_at: string
          requested_by: string | null
          requested_from: string | null
          status: Database["public"]["Enums"]["approval_status"]
        }
        Insert: {
          approval_level: string
          comp_earning_id: string
          completed_at?: string | null
          due_at?: string | null
          id?: string
          notes?: string | null
          requested_at?: string
          requested_by?: string | null
          requested_from?: string | null
          status?: Database["public"]["Enums"]["approval_status"]
        }
        Update: {
          approval_level?: string
          comp_earning_id?: string
          completed_at?: string | null
          due_at?: string | null
          id?: string
          notes?: string | null
          requested_at?: string
          requested_by?: string | null
          requested_from?: string | null
          status?: Database["public"]["Enums"]["approval_status"]
        }
        Relationships: [
          {
            foreignKeyName: "approval_requests_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "approval_requests_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_requests_requested_from_fkey"
            columns: ["requested_from"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_calculations: {
        Row: {
          calculated_at: string | null
          calculated_by: string | null
          calculation_version: number
          comp_period_id: string
          created_at: string
          employee_id: string
          id: string
          notes: string | null
          total_approved: number
          total_earned: number
          total_eligible: number
          total_paid: number
          updated_at: string
        }
        Insert: {
          calculated_at?: string | null
          calculated_by?: string | null
          calculation_version?: number
          comp_period_id: string
          created_at?: string
          employee_id: string
          id?: string
          notes?: string | null
          total_approved?: number
          total_earned?: number
          total_eligible?: number
          total_paid?: number
          updated_at?: string
        }
        Update: {
          calculated_at?: string | null
          calculated_by?: string | null
          calculation_version?: number
          comp_period_id?: string
          created_at?: string
          employee_id?: string
          id?: string
          notes?: string | null
          total_approved?: number
          total_earned?: number
          total_eligible?: number
          total_paid?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comp_calculations_calculated_by_fkey"
            columns: ["calculated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_calculations_comp_period_id_fkey"
            columns: ["comp_period_id"]
            isOneToOne: false
            referencedRelation: "comp_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_calculations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "comp_calculations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_component_deal_rules: {
        Row: {
          amount_label: string | null
          amount_source: string | null
          calculation_action: string
          created_at: string
          effective_end_date: string | null
          effective_start_date: string | null
          hubspot_deal_type: string
          hubspot_pipeline_id: string
          hubspot_stage_id: string
          id: string
          is_active: boolean
          marks_earned: boolean
          marks_eligible: boolean
          marks_paid: boolean
          plan_component_id: string
          priority: number
          rule_notes: string | null
          updated_at: string
        }
        Insert: {
          amount_label?: string | null
          amount_source?: string | null
          calculation_action?: string
          created_at?: string
          effective_end_date?: string | null
          effective_start_date?: string | null
          hubspot_deal_type: string
          hubspot_pipeline_id: string
          hubspot_stage_id: string
          id?: string
          is_active?: boolean
          marks_earned?: boolean
          marks_eligible?: boolean
          marks_paid?: boolean
          plan_component_id: string
          priority?: number
          rule_notes?: string | null
          updated_at?: string
        }
        Update: {
          amount_label?: string | null
          amount_source?: string | null
          calculation_action?: string
          created_at?: string
          effective_end_date?: string | null
          effective_start_date?: string | null
          hubspot_deal_type?: string
          hubspot_pipeline_id?: string
          hubspot_stage_id?: string
          id?: string
          is_active?: boolean
          marks_earned?: boolean
          marks_eligible?: boolean
          marks_paid?: boolean
          plan_component_id?: string
          priority?: number
          rule_notes?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comp_component_deal_rules_hubspot_deal_type_fkey"
            columns: ["hubspot_deal_type"]
            isOneToOne: false
            referencedRelation: "hubspot_deal_types"
            referencedColumns: ["internal_value"]
          },
          {
            foreignKeyName: "comp_component_deal_rules_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_component_id"]
          },
          {
            foreignKeyName: "comp_component_deal_rules_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_plan_components"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_credit_rules: {
        Row: {
          allow_stacking: boolean
          created_at: string
          credit_method: Database["public"]["Enums"]["credit_method"]
          credit_percentage: number
          effective_end_date: string | null
          effective_start_date: string
          id: string
          named_employee_id: string | null
          plan_component_id: string
          priority: number
          qualifying_deal_types: Json
          qualifying_pipeline_ids: Json
          rule_configuration: Json
        }
        Insert: {
          allow_stacking?: boolean
          created_at?: string
          credit_method: Database["public"]["Enums"]["credit_method"]
          credit_percentage?: number
          effective_end_date?: string | null
          effective_start_date: string
          id?: string
          named_employee_id?: string | null
          plan_component_id: string
          priority?: number
          qualifying_deal_types?: Json
          qualifying_pipeline_ids?: Json
          rule_configuration?: Json
        }
        Update: {
          allow_stacking?: boolean
          created_at?: string
          credit_method?: Database["public"]["Enums"]["credit_method"]
          credit_percentage?: number
          effective_end_date?: string | null
          effective_start_date?: string
          id?: string
          named_employee_id?: string | null
          plan_component_id?: string
          priority?: number
          qualifying_deal_types?: Json
          qualifying_pipeline_ids?: Json
          rule_configuration?: Json
        }
        Relationships: [
          {
            foreignKeyName: "comp_credit_rules_named_employee_id_fkey"
            columns: ["named_employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "comp_credit_rules_named_employee_id_fkey"
            columns: ["named_employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_credit_rules_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_component_id"]
          },
          {
            foreignKeyName: "comp_credit_rules_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_plan_components"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_deal_credit_reviews: {
        Row: {
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_notes: string | null
          employee_id: string
          hubspot_deal_id: string
          id: string
          plan_component_id: string
          review_question: string
          review_status: string
          review_type: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_notes?: string | null
          employee_id: string
          hubspot_deal_id: string
          id?: string
          plan_component_id: string
          review_question: string
          review_status?: string
          review_type: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_notes?: string | null
          employee_id?: string
          hubspot_deal_id?: string
          id?: string
          plan_component_id?: string
          review_question?: string
          review_status?: string
          review_type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comp_deal_credit_reviews_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "comp_deal_credit_reviews_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_deal_credit_reviews_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_component_id"]
          },
          {
            foreignKeyName: "comp_deal_credit_reviews_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_plan_components"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_earning_lifecycle_events: {
        Row: {
          comp_earning_id: string | null
          created_at: string
          employee_id: string
          event_reason: string
          event_source: string
          event_type: string
          hubspot_deal_id: string | null
          hubspot_sync_run_id: string | null
          id: string
          new_state: Json
          new_status: string | null
          occurred_at: string
          plan_assignment_id: string | null
          plan_component_id: string | null
          previous_state: Json
          previous_status: string | null
          requires_review: boolean
          review_notes: string | null
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
        }
        Insert: {
          comp_earning_id?: string | null
          created_at?: string
          employee_id: string
          event_reason: string
          event_source: string
          event_type: string
          hubspot_deal_id?: string | null
          hubspot_sync_run_id?: string | null
          id?: string
          new_state?: Json
          new_status?: string | null
          occurred_at?: string
          plan_assignment_id?: string | null
          plan_component_id?: string | null
          previous_state?: Json
          previous_status?: string | null
          requires_review?: boolean
          review_notes?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
        }
        Update: {
          comp_earning_id?: string | null
          created_at?: string
          employee_id?: string
          event_reason?: string
          event_source?: string
          event_type?: string
          hubspot_deal_id?: string | null
          hubspot_sync_run_id?: string | null
          id?: string
          new_state?: Json
          new_status?: string | null
          occurred_at?: string
          plan_assignment_id?: string | null
          plan_component_id?: string | null
          previous_state?: Json
          previous_status?: string | null
          requires_review?: boolean
          review_notes?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "comp_earning_lifecycle_events_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_hubspot_sync_run_id_fkey"
            columns: ["hubspot_sync_run_id"]
            isOneToOne: false
            referencedRelation: "hubspot_sync_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_plan_assignment_id_fkey"
            columns: ["plan_assignment_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_assignment_id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_plan_assignment_id_fkey"
            columns: ["plan_assignment_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["plan_assignment_id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_plan_assignment_id_fkey"
            columns: ["plan_assignment_id"]
            isOneToOne: false
            referencedRelation: "employee_plan_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_component_id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_plan_components"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earning_lifecycle_events_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_earnings: {
        Row: {
          approved_amount: number
          calculation_id: string
          created_at: string
          earned_amount: number
          earned_date: string
          earning_description: string | null
          earning_name: string
          earning_origin: Database["public"]["Enums"]["earning_origin"]
          eligibility_condition_description: string | null
          eligibility_condition_type: string | null
          eligibility_due_date: string | null
          eligibility_evidence: Json
          eligibility_status: Database["public"]["Enums"]["eligibility_status"]
          eligible_amount: number
          eligible_date: string | null
          employee_id: string
          employee_verification_notes: string | null
          employee_verification_status: Database["public"]["Enums"]["verification_status"]
          employee_verified_at: string | null
          executive_approval_notes: string | null
          executive_approval_required: boolean
          executive_approval_status: Database["public"]["Enums"]["approval_status"]
          executive_approved_at: string | null
          executive_approved_by: string | null
          expected_pay_period_label: string | null
          expected_payment_date: string | null
          historical_reference: string | null
          hold_reason: string | null
          id: string
          is_current: boolean
          manager_approval_notes: string | null
          manager_approval_status: Database["public"]["Enums"]["approval_status"]
          manager_approved_at: string | null
          manager_approved_by: string | null
          paid_amount: number
          payment_status: Database["public"]["Enums"]["payment_status"]
          plan_assignment_id: string | null
          plan_component_id: string | null
          reconciled_at: string | null
          reconciled_by: string | null
          reconciliation_notes: string | null
          reconciliation_status: Database["public"]["Enums"]["reconciliation_status"]
          source_external_id: string | null
          source_match_status: Database["public"]["Enums"]["source_match_status"]
          source_snapshot: Json
          source_type: string | null
          source_url: string | null
          supersedes_earning_id: string | null
          updated_at: string
        }
        Insert: {
          approved_amount?: number
          calculation_id: string
          created_at?: string
          earned_amount?: number
          earned_date: string
          earning_description?: string | null
          earning_name: string
          earning_origin?: Database["public"]["Enums"]["earning_origin"]
          eligibility_condition_description?: string | null
          eligibility_condition_type?: string | null
          eligibility_due_date?: string | null
          eligibility_evidence?: Json
          eligibility_status?: Database["public"]["Enums"]["eligibility_status"]
          eligible_amount?: number
          eligible_date?: string | null
          employee_id: string
          employee_verification_notes?: string | null
          employee_verification_status?: Database["public"]["Enums"]["verification_status"]
          employee_verified_at?: string | null
          executive_approval_notes?: string | null
          executive_approval_required?: boolean
          executive_approval_status?: Database["public"]["Enums"]["approval_status"]
          executive_approved_at?: string | null
          executive_approved_by?: string | null
          expected_pay_period_label?: string | null
          expected_payment_date?: string | null
          historical_reference?: string | null
          hold_reason?: string | null
          id?: string
          is_current?: boolean
          manager_approval_notes?: string | null
          manager_approval_status?: Database["public"]["Enums"]["approval_status"]
          manager_approved_at?: string | null
          manager_approved_by?: string | null
          paid_amount?: number
          payment_status?: Database["public"]["Enums"]["payment_status"]
          plan_assignment_id?: string | null
          plan_component_id?: string | null
          reconciled_at?: string | null
          reconciled_by?: string | null
          reconciliation_notes?: string | null
          reconciliation_status?: Database["public"]["Enums"]["reconciliation_status"]
          source_external_id?: string | null
          source_match_status?: Database["public"]["Enums"]["source_match_status"]
          source_snapshot?: Json
          source_type?: string | null
          source_url?: string | null
          supersedes_earning_id?: string | null
          updated_at?: string
        }
        Update: {
          approved_amount?: number
          calculation_id?: string
          created_at?: string
          earned_amount?: number
          earned_date?: string
          earning_description?: string | null
          earning_name?: string
          earning_origin?: Database["public"]["Enums"]["earning_origin"]
          eligibility_condition_description?: string | null
          eligibility_condition_type?: string | null
          eligibility_due_date?: string | null
          eligibility_evidence?: Json
          eligibility_status?: Database["public"]["Enums"]["eligibility_status"]
          eligible_amount?: number
          eligible_date?: string | null
          employee_id?: string
          employee_verification_notes?: string | null
          employee_verification_status?: Database["public"]["Enums"]["verification_status"]
          employee_verified_at?: string | null
          executive_approval_notes?: string | null
          executive_approval_required?: boolean
          executive_approval_status?: Database["public"]["Enums"]["approval_status"]
          executive_approved_at?: string | null
          executive_approved_by?: string | null
          expected_pay_period_label?: string | null
          expected_payment_date?: string | null
          historical_reference?: string | null
          hold_reason?: string | null
          id?: string
          is_current?: boolean
          manager_approval_notes?: string | null
          manager_approval_status?: Database["public"]["Enums"]["approval_status"]
          manager_approved_at?: string | null
          manager_approved_by?: string | null
          paid_amount?: number
          payment_status?: Database["public"]["Enums"]["payment_status"]
          plan_assignment_id?: string | null
          plan_component_id?: string | null
          reconciled_at?: string | null
          reconciled_by?: string | null
          reconciliation_notes?: string | null
          reconciliation_status?: Database["public"]["Enums"]["reconciliation_status"]
          source_external_id?: string | null
          source_match_status?: Database["public"]["Enums"]["source_match_status"]
          source_snapshot?: Json
          source_type?: string | null
          source_url?: string | null
          supersedes_earning_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comp_earnings_calculation_id_fkey"
            columns: ["calculation_id"]
            isOneToOne: false
            referencedRelation: "comp_calculations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earnings_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "comp_earnings_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earnings_executive_approved_by_fkey"
            columns: ["executive_approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earnings_manager_approved_by_fkey"
            columns: ["manager_approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earnings_plan_assignment_id_fkey"
            columns: ["plan_assignment_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_assignment_id"]
          },
          {
            foreignKeyName: "comp_earnings_plan_assignment_id_fkey"
            columns: ["plan_assignment_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["plan_assignment_id"]
          },
          {
            foreignKeyName: "comp_earnings_plan_assignment_id_fkey"
            columns: ["plan_assignment_id"]
            isOneToOne: false
            referencedRelation: "employee_plan_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earnings_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_component_id"]
          },
          {
            foreignKeyName: "comp_earnings_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_plan_components"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earnings_reconciled_by_fkey"
            columns: ["reconciled_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_earnings_supersedes_earning_id_fkey"
            columns: ["supersedes_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "comp_earnings_supersedes_earning_id_fkey"
            columns: ["supersedes_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_import_batches: {
        Row: {
          batch_name: string
          created_at: string
          employee_id: string | null
          error_rows: number
          id: string
          imported_at: string
          imported_by: string | null
          notes: string | null
          processed_rows: number
          source_filename: string | null
          source_period_end: string | null
          source_period_start: string | null
          source_type: string
          status: string
          total_rows: number
          updated_at: string
        }
        Insert: {
          batch_name: string
          created_at?: string
          employee_id?: string | null
          error_rows?: number
          id?: string
          imported_at?: string
          imported_by?: string | null
          notes?: string | null
          processed_rows?: number
          source_filename?: string | null
          source_period_end?: string | null
          source_period_start?: string | null
          source_type: string
          status?: string
          total_rows?: number
          updated_at?: string
        }
        Update: {
          batch_name?: string
          created_at?: string
          employee_id?: string | null
          error_rows?: number
          id?: string
          imported_at?: string
          imported_by?: string | null
          notes?: string | null
          processed_rows?: number
          source_filename?: string | null
          source_period_end?: string | null
          source_period_start?: string | null
          source_type?: string
          status?: string
          total_rows?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comp_import_batches_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "comp_import_batches_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_import_batches_imported_by_fkey"
            columns: ["imported_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_periods: {
        Row: {
          created_at: string
          end_date: string
          id: string
          locked_at: string | null
          locked_by: string | null
          name: string
          payment_target_date: string | null
          period_type: string
          start_date: string
          status: Database["public"]["Enums"]["comp_period_status"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          end_date: string
          id?: string
          locked_at?: string | null
          locked_by?: string | null
          name: string
          payment_target_date?: string | null
          period_type?: string
          start_date: string
          status?: Database["public"]["Enums"]["comp_period_status"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          end_date?: string
          id?: string
          locked_at?: string | null
          locked_by?: string | null
          name?: string
          payment_target_date?: string | null
          period_type?: string
          start_date?: string
          status?: Database["public"]["Enums"]["comp_period_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comp_periods_locked_by_fkey"
            columns: ["locked_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_plan_components: {
        Row: {
          allow_manager_payout_override: boolean
          calculation_order: number
          calculation_type: string
          component_code: string
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          maximum_payout: number | null
          measurement_label: string | null
          measurement_period: string
          measurement_source: string | null
          name: string
          payout_timing_method: Database["public"]["Enums"]["payout_timing_method"]
          plan_version_id: string
          rule_configuration: Json
          updated_at: string
        }
        Insert: {
          allow_manager_payout_override?: boolean
          calculation_order?: number
          calculation_type: string
          component_code: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          maximum_payout?: number | null
          measurement_label?: string | null
          measurement_period?: string
          measurement_source?: string | null
          name: string
          payout_timing_method?: Database["public"]["Enums"]["payout_timing_method"]
          plan_version_id: string
          rule_configuration?: Json
          updated_at?: string
        }
        Update: {
          allow_manager_payout_override?: boolean
          calculation_order?: number
          calculation_type?: string
          component_code?: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          maximum_payout?: number | null
          measurement_label?: string | null
          measurement_period?: string
          measurement_source?: string | null
          name?: string
          payout_timing_method?: Database["public"]["Enums"]["payout_timing_method"]
          plan_version_id?: string
          rule_configuration?: Json
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comp_plan_components_plan_version_id_fkey"
            columns: ["plan_version_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_version_id"]
          },
          {
            foreignKeyName: "comp_plan_components_plan_version_id_fkey"
            columns: ["plan_version_id"]
            isOneToOne: false
            referencedRelation: "comp_plan_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_plan_versions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          comp_plan_id: string
          created_at: string
          currency_code: string
          effective_end_date: string | null
          effective_start_date: string
          id: string
          notes: string | null
          status: Database["public"]["Enums"]["plan_version_status"]
          updated_at: string
          version_number: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          comp_plan_id: string
          created_at?: string
          currency_code?: string
          effective_end_date?: string | null
          effective_start_date: string
          id?: string
          notes?: string | null
          status?: Database["public"]["Enums"]["plan_version_status"]
          updated_at?: string
          version_number: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          comp_plan_id?: string
          created_at?: string
          currency_code?: string
          effective_end_date?: string | null
          effective_start_date?: string
          id?: string
          notes?: string | null
          status?: Database["public"]["Enums"]["plan_version_status"]
          updated_at?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "comp_plan_versions_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comp_plan_versions_comp_plan_id_fkey"
            columns: ["comp_plan_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["comp_plan_id"]
          },
          {
            foreignKeyName: "comp_plan_versions_comp_plan_id_fkey"
            columns: ["comp_plan_id"]
            isOneToOne: false
            referencedRelation: "comp_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      comp_plans: {
        Row: {
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          owner_id: string | null
          plan_code: string
          plan_type: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          owner_id?: string | null
          plan_code: string
          plan_type?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          owner_id?: string | null
          plan_code?: string
          plan_type?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comp_plans_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      contract_group_deals: {
        Row: {
          contract_group_id: string
          contract_year_number: number | null
          created_at: string
          expected_payment_date: string | null
          hubspot_deal_id: string
          id: string
        }
        Insert: {
          contract_group_id: string
          contract_year_number?: number | null
          created_at?: string
          expected_payment_date?: string | null
          hubspot_deal_id: string
          id?: string
        }
        Update: {
          contract_group_id?: string
          contract_year_number?: number | null
          created_at?: string
          expected_payment_date?: string | null
          hubspot_deal_id?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "contract_group_deals_contract_group_id_fkey"
            columns: ["contract_group_id"]
            isOneToOne: false
            referencedRelation: "contract_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contract_group_deals_hubspot_deal_id_fkey"
            columns: ["hubspot_deal_id"]
            isOneToOne: false
            referencedRelation: "hubspot_compensation_deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contract_group_deals_hubspot_deal_id_fkey"
            columns: ["hubspot_deal_id"]
            isOneToOne: false
            referencedRelation: "hubspot_deal_scope"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contract_group_deals_hubspot_deal_id_fkey"
            columns: ["hubspot_deal_id"]
            isOneToOne: false
            referencedRelation: "hubspot_deals"
            referencedColumns: ["id"]
          },
        ]
      }
      contract_groups: {
        Row: {
          average_arr: number | null
          confirmed: boolean
          confirmed_at: string | null
          confirmed_by: string | null
          contract_end_date: string | null
          contract_external_reference: string | null
          contract_name: string
          contract_start_date: string | null
          contract_term_years: number | null
          created_at: string
          customer_account_id: string | null
          default_payout_timing: Database["public"]["Enums"]["payout_timing_method"]
          grouping_notes: string | null
          id: string
          updated_at: string
        }
        Insert: {
          average_arr?: number | null
          confirmed?: boolean
          confirmed_at?: string | null
          confirmed_by?: string | null
          contract_end_date?: string | null
          contract_external_reference?: string | null
          contract_name: string
          contract_start_date?: string | null
          contract_term_years?: number | null
          created_at?: string
          customer_account_id?: string | null
          default_payout_timing?: Database["public"]["Enums"]["payout_timing_method"]
          grouping_notes?: string | null
          id?: string
          updated_at?: string
        }
        Update: {
          average_arr?: number | null
          confirmed?: boolean
          confirmed_at?: string | null
          confirmed_by?: string | null
          contract_end_date?: string | null
          contract_external_reference?: string | null
          contract_name?: string
          contract_start_date?: string | null
          contract_term_years?: number | null
          created_at?: string
          customer_account_id?: string | null
          default_payout_timing?: Database["public"]["Enums"]["payout_timing_method"]
          grouping_notes?: string | null
          id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contract_groups_confirmed_by_fkey"
            columns: ["confirmed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contract_groups_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      contract_payout_overrides: {
        Row: {
          approved_at: string
          approved_by: string
          contract_group_id: string
          created_at: string
          id: string
          is_active: boolean
          new_method: Database["public"]["Enums"]["payout_timing_method"]
          override_reason: string
          previous_method: Database["public"]["Enums"]["payout_timing_method"]
        }
        Insert: {
          approved_at?: string
          approved_by: string
          contract_group_id: string
          created_at?: string
          id?: string
          is_active?: boolean
          new_method: Database["public"]["Enums"]["payout_timing_method"]
          override_reason: string
          previous_method: Database["public"]["Enums"]["payout_timing_method"]
        }
        Update: {
          approved_at?: string
          approved_by?: string
          contract_group_id?: string
          created_at?: string
          id?: string
          is_active?: boolean
          new_method?: Database["public"]["Enums"]["payout_timing_method"]
          override_reason?: string
          previous_method?: Database["public"]["Enums"]["payout_timing_method"]
        }
        Relationships: [
          {
            foreignKeyName: "contract_payout_overrides_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contract_payout_overrides_contract_group_id_fkey"
            columns: ["contract_group_id"]
            isOneToOne: false
            referencedRelation: "contract_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_accounts: {
        Row: {
          account_name: string
          annual_recurring_revenue: number | null
          contract_end_date: string | null
          contract_start_date: string | null
          created_at: string
          customer_status: string | null
          hubspot_company_id: string | null
          hubspot_data: Json
          id: string
          is_active: boolean
          last_synced_at: string | null
          updated_at: string
        }
        Insert: {
          account_name: string
          annual_recurring_revenue?: number | null
          contract_end_date?: string | null
          contract_start_date?: string | null
          created_at?: string
          customer_status?: string | null
          hubspot_company_id?: string | null
          hubspot_data?: Json
          id?: string
          is_active?: boolean
          last_synced_at?: string | null
          updated_at?: string
        }
        Update: {
          account_name?: string
          annual_recurring_revenue?: number | null
          contract_end_date?: string | null
          contract_start_date?: string | null
          created_at?: string
          customer_status?: string | null
          hubspot_company_id?: string | null
          hubspot_data?: Json
          id?: string
          is_active?: boolean
          last_synced_at?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      deal_credit_allocations: {
        Row: {
          adjusted_by: string | null
          adjustment_reason: string | null
          allocation_source: string
          commissionable_amount: number
          created_at: string
          credit_method: Database["public"]["Enums"]["credit_method"]
          credit_percentage: number
          employee_id: string
          hubspot_deal_id: string
          id: string
          manually_adjusted: boolean
          plan_component_id: string | null
          updated_at: string
        }
        Insert: {
          adjusted_by?: string | null
          adjustment_reason?: string | null
          allocation_source?: string
          commissionable_amount?: number
          created_at?: string
          credit_method: Database["public"]["Enums"]["credit_method"]
          credit_percentage: number
          employee_id: string
          hubspot_deal_id: string
          id?: string
          manually_adjusted?: boolean
          plan_component_id?: string | null
          updated_at?: string
        }
        Update: {
          adjusted_by?: string | null
          adjustment_reason?: string | null
          allocation_source?: string
          commissionable_amount?: number
          created_at?: string
          credit_method?: Database["public"]["Enums"]["credit_method"]
          credit_percentage?: number
          employee_id?: string
          hubspot_deal_id?: string
          id?: string
          manually_adjusted?: boolean
          plan_component_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "deal_credit_allocations_adjusted_by_fkey"
            columns: ["adjusted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_credit_allocations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "deal_credit_allocations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_credit_allocations_hubspot_deal_id_fkey"
            columns: ["hubspot_deal_id"]
            isOneToOne: false
            referencedRelation: "hubspot_compensation_deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_credit_allocations_hubspot_deal_id_fkey"
            columns: ["hubspot_deal_id"]
            isOneToOne: false
            referencedRelation: "hubspot_deal_scope"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_credit_allocations_hubspot_deal_id_fkey"
            columns: ["hubspot_deal_id"]
            isOneToOne: false
            referencedRelation: "hubspot_deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deal_credit_allocations_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_component_id"]
          },
          {
            foreignKeyName: "deal_credit_allocations_plan_component_id_fkey"
            columns: ["plan_component_id"]
            isOneToOne: false
            referencedRelation: "comp_plan_components"
            referencedColumns: ["id"]
          },
        ]
      }
      earning_adjustments: {
        Row: {
          adjustment_type: Database["public"]["Enums"]["adjustment_type"]
          amount: number
          approval_status: Database["public"]["Enums"]["approval_status"]
          approved_at: string | null
          approved_by: string | null
          comp_earning_id: string | null
          comp_period_id: string | null
          created_at: string
          effective_date: string
          employee_id: string
          id: string
          reason: string
          requested_by: string | null
          source_hubspot_deal_id: string | null
          supporting_details: Json
          updated_at: string
        }
        Insert: {
          adjustment_type: Database["public"]["Enums"]["adjustment_type"]
          amount: number
          approval_status?: Database["public"]["Enums"]["approval_status"]
          approved_at?: string | null
          approved_by?: string | null
          comp_earning_id?: string | null
          comp_period_id?: string | null
          created_at?: string
          effective_date: string
          employee_id: string
          id?: string
          reason: string
          requested_by?: string | null
          source_hubspot_deal_id?: string | null
          supporting_details?: Json
          updated_at?: string
        }
        Update: {
          adjustment_type?: Database["public"]["Enums"]["adjustment_type"]
          amount?: number
          approval_status?: Database["public"]["Enums"]["approval_status"]
          approved_at?: string | null
          approved_by?: string | null
          comp_earning_id?: string | null
          comp_period_id?: string | null
          created_at?: string
          effective_date?: string
          employee_id?: string
          id?: string
          reason?: string
          requested_by?: string | null
          source_hubspot_deal_id?: string | null
          supporting_details?: Json
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "earning_adjustments_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_adjustments_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "earning_adjustments_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_adjustments_comp_period_id_fkey"
            columns: ["comp_period_id"]
            isOneToOne: false
            referencedRelation: "comp_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_adjustments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "earning_adjustments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_adjustments_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_adjustments_source_hubspot_deal_id_fkey"
            columns: ["source_hubspot_deal_id"]
            isOneToOne: false
            referencedRelation: "hubspot_compensation_deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_adjustments_source_hubspot_deal_id_fkey"
            columns: ["source_hubspot_deal_id"]
            isOneToOne: false
            referencedRelation: "hubspot_deal_scope"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_adjustments_source_hubspot_deal_id_fkey"
            columns: ["source_hubspot_deal_id"]
            isOneToOne: false
            referencedRelation: "hubspot_deals"
            referencedColumns: ["id"]
          },
        ]
      }
      earning_disputes: {
        Row: {
          assigned_to: string | null
          comp_earning_id: string | null
          created_at: string
          description: string
          dispute_type: string
          employee_id: string
          historical_comp_record_id: string | null
          id: string
          requested_amount: number | null
          resolution: string | null
          resolved_at: string | null
          resolved_by: string | null
          status: string
          submitted_by: string | null
          updated_at: string
        }
        Insert: {
          assigned_to?: string | null
          comp_earning_id?: string | null
          created_at?: string
          description: string
          dispute_type: string
          employee_id: string
          historical_comp_record_id?: string | null
          id?: string
          requested_amount?: number | null
          resolution?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
          submitted_by?: string | null
          updated_at?: string
        }
        Update: {
          assigned_to?: string | null
          comp_earning_id?: string | null
          created_at?: string
          description?: string
          dispute_type?: string
          employee_id?: string
          historical_comp_record_id?: string | null
          id?: string
          requested_amount?: number | null
          resolution?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
          submitted_by?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "earning_disputes_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_disputes_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "earning_disputes_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_disputes_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "earning_disputes_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_disputes_historical_comp_record_id_fkey"
            columns: ["historical_comp_record_id"]
            isOneToOne: false
            referencedRelation: "historical_comp_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_disputes_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_disputes_submitted_by_fkey"
            columns: ["submitted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      earning_eligibility_events: {
        Row: {
          changed_at: string
          changed_by: string | null
          comp_earning_id: string
          event_source: string
          evidence: Json
          id: string
          new_status: Database["public"]["Enums"]["eligibility_status"]
          notes: string | null
          previous_status:
            | Database["public"]["Enums"]["eligibility_status"]
            | null
          source_external_id: string | null
        }
        Insert: {
          changed_at?: string
          changed_by?: string | null
          comp_earning_id: string
          event_source: string
          evidence?: Json
          id?: string
          new_status: Database["public"]["Enums"]["eligibility_status"]
          notes?: string | null
          previous_status?:
            | Database["public"]["Enums"]["eligibility_status"]
            | null
          source_external_id?: string | null
        }
        Update: {
          changed_at?: string
          changed_by?: string | null
          comp_earning_id?: string
          event_source?: string
          evidence?: Json
          id?: string
          new_status?: Database["public"]["Enums"]["eligibility_status"]
          notes?: string | null
          previous_status?:
            | Database["public"]["Enums"]["eligibility_status"]
            | null
          source_external_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "earning_eligibility_events_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_eligibility_events_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "earning_eligibility_events_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
        ]
      }
      earning_payment_schedules: {
        Row: {
          comp_earning_id: string
          created_at: string
          expected_pay_period_label: string | null
          expected_payment_date: string | null
          id: string
          schedule_reason: string | null
          schedule_status: string
          scheduled_amount: number
          scheduled_by: string | null
          superseded_by_id: string | null
          updated_at: string
        }
        Insert: {
          comp_earning_id: string
          created_at?: string
          expected_pay_period_label?: string | null
          expected_payment_date?: string | null
          id?: string
          schedule_reason?: string | null
          schedule_status?: string
          scheduled_amount: number
          scheduled_by?: string | null
          superseded_by_id?: string | null
          updated_at?: string
        }
        Update: {
          comp_earning_id?: string
          created_at?: string
          expected_pay_period_label?: string | null
          expected_payment_date?: string | null
          id?: string
          schedule_reason?: string | null
          schedule_status?: string
          scheduled_amount?: number
          scheduled_by?: string | null
          superseded_by_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "earning_payment_schedules_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "earning_payment_schedules_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_payment_schedules_scheduled_by_fkey"
            columns: ["scheduled_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earning_payment_schedules_superseded_by_id_fkey"
            columns: ["superseded_by_id"]
            isOneToOne: false
            referencedRelation: "earning_payment_schedules"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_book_accounts: {
        Row: {
          baseline_arr: number | null
          baseline_status: string | null
          created_at: string
          customer_account_id: string
          employee_book_id: string
          id: string
          included_from: string | null
          included_through: string | null
          inclusion_reason: string | null
        }
        Insert: {
          baseline_arr?: number | null
          baseline_status?: string | null
          created_at?: string
          customer_account_id: string
          employee_book_id: string
          id?: string
          included_from?: string | null
          included_through?: string | null
          inclusion_reason?: string | null
        }
        Update: {
          baseline_arr?: number | null
          baseline_status?: string | null
          created_at?: string
          customer_account_id?: string
          employee_book_id?: string
          id?: string
          included_from?: string | null
          included_through?: string | null
          inclusion_reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_book_accounts_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_book_accounts_employee_book_id_fkey"
            columns: ["employee_book_id"]
            isOneToOne: false
            referencedRelation: "employee_books"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_books: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          baseline_account_count: number | null
          baseline_arr: number | null
          book_name: string
          book_type: string
          book_year: number
          created_at: string
          employee_id: string
          id: string
          notes: string | null
          snapshot_date: string
          status: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          baseline_account_count?: number | null
          baseline_arr?: number | null
          book_name: string
          book_type?: string
          book_year: number
          created_at?: string
          employee_id: string
          id?: string
          notes?: string | null
          snapshot_date: string
          status?: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          baseline_account_count?: number | null
          baseline_arr?: number | null
          book_name?: string
          book_type?: string
          book_year?: number
          created_at?: string
          employee_id?: string
          id?: string
          notes?: string | null
          snapshot_date?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_books_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_books_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_books_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_job_roles: {
        Row: {
          allocation_percent: number | null
          created_at: string
          effective_end_date: string | null
          effective_start_date: string
          employee_id: string
          id: string
          is_primary: boolean
          job_role_id: string
        }
        Insert: {
          allocation_percent?: number | null
          created_at?: string
          effective_end_date?: string | null
          effective_start_date: string
          employee_id: string
          id?: string
          is_primary?: boolean
          job_role_id: string
        }
        Update: {
          allocation_percent?: number | null
          created_at?: string
          effective_end_date?: string | null
          effective_start_date?: string
          employee_id?: string
          id?: string
          is_primary?: boolean
          job_role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_job_roles_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_job_roles_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_job_roles_job_role_id_fkey"
            columns: ["job_role_id"]
            isOneToOne: false
            referencedRelation: "job_roles"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_plan_assignments: {
        Row: {
          allocation_percent: number
          assigned_by: string | null
          assignment_notes: string | null
          created_at: string
          earnings_eligibility_date: string | null
          effective_end_date: string | null
          effective_start_date: string
          eligibility_waiting_period_days: number | null
          employee_id: string
          id: string
          plan_version_id: string
          related_job_role_id: string | null
          updated_at: string
        }
        Insert: {
          allocation_percent?: number
          assigned_by?: string | null
          assignment_notes?: string | null
          created_at?: string
          earnings_eligibility_date?: string | null
          effective_end_date?: string | null
          effective_start_date: string
          eligibility_waiting_period_days?: number | null
          employee_id: string
          id?: string
          plan_version_id: string
          related_job_role_id?: string | null
          updated_at?: string
        }
        Update: {
          allocation_percent?: number
          assigned_by?: string | null
          assignment_notes?: string | null
          created_at?: string
          earnings_eligibility_date?: string | null
          effective_end_date?: string | null
          effective_start_date?: string
          eligibility_waiting_period_days?: number | null
          employee_id?: string
          id?: string
          plan_version_id?: string
          related_job_role_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_plan_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_plan_assignments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_plan_assignments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_plan_assignments_plan_version_id_fkey"
            columns: ["plan_version_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["plan_version_id"]
          },
          {
            foreignKeyName: "employee_plan_assignments_plan_version_id_fkey"
            columns: ["plan_version_id"]
            isOneToOne: false
            referencedRelation: "comp_plan_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_plan_assignments_related_job_role_id_fkey"
            columns: ["related_job_role_id"]
            isOneToOne: false
            referencedRelation: "job_roles"
            referencedColumns: ["id"]
          },
        ]
      }
      employees: {
        Row: {
          created_at: string
          department: string | null
          email: string
          employee_number: string | null
          full_name: string
          hire_date: string | null
          hubspot_owner_id: string | null
          id: string
          is_active: boolean
          job_title: string | null
          manager_id: string | null
          termination_date: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          department?: string | null
          email: string
          employee_number?: string | null
          full_name: string
          hire_date?: string | null
          hubspot_owner_id?: string | null
          id?: string
          is_active?: boolean
          job_title?: string | null
          manager_id?: string | null
          termination_date?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          department?: string | null
          email?: string
          employee_number?: string | null
          full_name?: string
          hire_date?: string | null
          hubspot_owner_id?: string | null
          id?: string
          is_active?: boolean
          job_title?: string | null
          manager_id?: string | null
          termination_date?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "employees_manager_id_fkey"
            columns: ["manager_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employees_manager_id_fkey"
            columns: ["manager_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      historical_comp_records: {
        Row: {
          claimed_approved_amount: number | null
          claimed_earned_amount: number | null
          claimed_paid_amount: number | null
          created_at: string
          earning_category: string | null
          earning_date: string | null
          earning_description: string | null
          employee_id: string
          expected_pay_period_label: string | null
          expected_payment_date: string | null
          external_source_id: string | null
          hubspot_company_id: string | null
          hubspot_deal_id: string | null
          id: string
          import_batch_id: string | null
          matched_comp_earning_id: string | null
          matched_hubspot_deal_record_id: string | null
          original_period_label: string | null
          original_row_data: Json
          reconciliation_status: Database["public"]["Enums"]["reconciliation_status"]
          reported_pay_period_label: string | null
          reported_payment_date: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          reviewer_notes: string | null
          source_match_status: Database["public"]["Enums"]["source_match_status"]
          source_record_url: string | null
          source_row_number: number | null
          updated_at: string
        }
        Insert: {
          claimed_approved_amount?: number | null
          claimed_earned_amount?: number | null
          claimed_paid_amount?: number | null
          created_at?: string
          earning_category?: string | null
          earning_date?: string | null
          earning_description?: string | null
          employee_id: string
          expected_pay_period_label?: string | null
          expected_payment_date?: string | null
          external_source_id?: string | null
          hubspot_company_id?: string | null
          hubspot_deal_id?: string | null
          id?: string
          import_batch_id?: string | null
          matched_comp_earning_id?: string | null
          matched_hubspot_deal_record_id?: string | null
          original_period_label?: string | null
          original_row_data?: Json
          reconciliation_status?: Database["public"]["Enums"]["reconciliation_status"]
          reported_pay_period_label?: string | null
          reported_payment_date?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          reviewer_notes?: string | null
          source_match_status?: Database["public"]["Enums"]["source_match_status"]
          source_record_url?: string | null
          source_row_number?: number | null
          updated_at?: string
        }
        Update: {
          claimed_approved_amount?: number | null
          claimed_earned_amount?: number | null
          claimed_paid_amount?: number | null
          created_at?: string
          earning_category?: string | null
          earning_date?: string | null
          earning_description?: string | null
          employee_id?: string
          expected_pay_period_label?: string | null
          expected_payment_date?: string | null
          external_source_id?: string | null
          hubspot_company_id?: string | null
          hubspot_deal_id?: string | null
          id?: string
          import_batch_id?: string | null
          matched_comp_earning_id?: string | null
          matched_hubspot_deal_record_id?: string | null
          original_period_label?: string | null
          original_row_data?: Json
          reconciliation_status?: Database["public"]["Enums"]["reconciliation_status"]
          reported_pay_period_label?: string | null
          reported_payment_date?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          reviewer_notes?: string | null
          source_match_status?: Database["public"]["Enums"]["source_match_status"]
          source_record_url?: string | null
          source_row_number?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "historical_comp_records_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "historical_comp_records_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "historical_comp_records_import_batch_id_fkey"
            columns: ["import_batch_id"]
            isOneToOne: false
            referencedRelation: "comp_import_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "historical_comp_records_matched_comp_earning_id_fkey"
            columns: ["matched_comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "historical_comp_records_matched_comp_earning_id_fkey"
            columns: ["matched_comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "historical_comp_records_matched_hubspot_deal_record_id_fkey"
            columns: ["matched_hubspot_deal_record_id"]
            isOneToOne: false
            referencedRelation: "hubspot_compensation_deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "historical_comp_records_matched_hubspot_deal_record_id_fkey"
            columns: ["matched_hubspot_deal_record_id"]
            isOneToOne: false
            referencedRelation: "hubspot_deal_scope"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "historical_comp_records_matched_hubspot_deal_record_id_fkey"
            columns: ["matched_hubspot_deal_record_id"]
            isOneToOne: false
            referencedRelation: "hubspot_deals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "historical_comp_records_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hubspot_companies: {
        Row: {
          annual_renewal_date: string | null
          arr_2025: number | null
          cancellation_date: string | null
          company_name: string
          created_at: string
          current_customer: string | null
          customer_end_date: string | null
          customer_experience_manager_id: string | null
          customer_since: string | null
          customer_status: string | null
          hubspot_company_id: string
          hubspot_created_at: string | null
          hubspot_owner_id: string | null
          hubspot_updated_at: string | null
          id: string
          last_change_detected_at: string | null
          last_synced_at: string | null
          raw_hubspot_data: Json
          source_fingerprint: string | null
          total_arr: number | null
          updated_at: string
        }
        Insert: {
          annual_renewal_date?: string | null
          arr_2025?: number | null
          cancellation_date?: string | null
          company_name: string
          created_at?: string
          current_customer?: string | null
          customer_end_date?: string | null
          customer_experience_manager_id?: string | null
          customer_since?: string | null
          customer_status?: string | null
          hubspot_company_id: string
          hubspot_created_at?: string | null
          hubspot_owner_id?: string | null
          hubspot_updated_at?: string | null
          id?: string
          last_change_detected_at?: string | null
          last_synced_at?: string | null
          raw_hubspot_data?: Json
          source_fingerprint?: string | null
          total_arr?: number | null
          updated_at?: string
        }
        Update: {
          annual_renewal_date?: string | null
          arr_2025?: number | null
          cancellation_date?: string | null
          company_name?: string
          created_at?: string
          current_customer?: string | null
          customer_end_date?: string | null
          customer_experience_manager_id?: string | null
          customer_since?: string | null
          customer_status?: string | null
          hubspot_company_id?: string
          hubspot_created_at?: string | null
          hubspot_owner_id?: string | null
          hubspot_updated_at?: string | null
          id?: string
          last_change_detected_at?: string | null
          last_synced_at?: string | null
          raw_hubspot_data?: Json
          source_fingerprint?: string | null
          total_arr?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      hubspot_deal_company_associations: {
        Row: {
          association_type: string | null
          created_at: string
          first_synced_at: string
          hubspot_company_id: string
          hubspot_deal_id: string
          id: string
          is_primary: boolean
          last_synced_at: string
          updated_at: string
        }
        Insert: {
          association_type?: string | null
          created_at?: string
          first_synced_at?: string
          hubspot_company_id: string
          hubspot_deal_id: string
          id?: string
          is_primary?: boolean
          last_synced_at?: string
          updated_at?: string
        }
        Update: {
          association_type?: string | null
          created_at?: string
          first_synced_at?: string
          hubspot_company_id?: string
          hubspot_deal_id?: string
          id?: string
          is_primary?: boolean
          last_synced_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      hubspot_deal_types: {
        Row: {
          created_at: string
          display_order: number
          displayed_name: string
          internal_value: string
          is_active: boolean
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          displayed_name: string
          internal_value: string
          is_active?: boolean
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          displayed_name?: string
          internal_value?: string
          is_active?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      hubspot_deals: {
        Row: {
          amount: number | null
          average_arr: number | null
          close_date: string | null
          contract_end_date: string | null
          contract_start_date: string | null
          contract_term_label: string | null
          contract_term_months: number | null
          contract_term_years: number | null
          contract_url: string | null
          created_at: string
          deal_name: string
          first_year_arr: number | null
          hubspot_company_id: string | null
          hubspot_created_at: string | null
          hubspot_deal_id: string
          hubspot_deal_type: string | null
          hubspot_owner_id: string | null
          hubspot_pipeline_id: string | null
          hubspot_record_url: string | null
          hubspot_stage_id: string | null
          hubspot_updated_at: string | null
          id: string
          invoice_paid_date: string | null
          last_change_detected_at: string | null
          last_synced_at: string | null
          one_time_fee: number | null
          payment_frequency: string | null
          raw_hubspot_data: Json
          source_fingerprint: string | null
          subscription_updated_date: string | null
          total_contract_value: number | null
          updated_at: string
        }
        Insert: {
          amount?: number | null
          average_arr?: number | null
          close_date?: string | null
          contract_end_date?: string | null
          contract_start_date?: string | null
          contract_term_label?: string | null
          contract_term_months?: number | null
          contract_term_years?: number | null
          contract_url?: string | null
          created_at?: string
          deal_name: string
          first_year_arr?: number | null
          hubspot_company_id?: string | null
          hubspot_created_at?: string | null
          hubspot_deal_id: string
          hubspot_deal_type?: string | null
          hubspot_owner_id?: string | null
          hubspot_pipeline_id?: string | null
          hubspot_record_url?: string | null
          hubspot_stage_id?: string | null
          hubspot_updated_at?: string | null
          id?: string
          invoice_paid_date?: string | null
          last_change_detected_at?: string | null
          last_synced_at?: string | null
          one_time_fee?: number | null
          payment_frequency?: string | null
          raw_hubspot_data?: Json
          source_fingerprint?: string | null
          subscription_updated_date?: string | null
          total_contract_value?: number | null
          updated_at?: string
        }
        Update: {
          amount?: number | null
          average_arr?: number | null
          close_date?: string | null
          contract_end_date?: string | null
          contract_start_date?: string | null
          contract_term_label?: string | null
          contract_term_months?: number | null
          contract_term_years?: number | null
          contract_url?: string | null
          created_at?: string
          deal_name?: string
          first_year_arr?: number | null
          hubspot_company_id?: string | null
          hubspot_created_at?: string | null
          hubspot_deal_id?: string
          hubspot_deal_type?: string | null
          hubspot_owner_id?: string | null
          hubspot_pipeline_id?: string | null
          hubspot_record_url?: string | null
          hubspot_stage_id?: string | null
          hubspot_updated_at?: string | null
          id?: string
          invoice_paid_date?: string | null
          last_change_detected_at?: string | null
          last_synced_at?: string | null
          one_time_fee?: number | null
          payment_frequency?: string | null
          raw_hubspot_data?: Json
          source_fingerprint?: string | null
          subscription_updated_date?: string | null
          total_contract_value?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      hubspot_pipeline_stages: {
        Row: {
          created_at: string
          display_order: number | null
          hubspot_pipeline_id: string
          hubspot_stage_id: string
          id: string
          is_closed_lost: boolean
          is_closed_won: boolean
          is_customer_paid: boolean
          is_invoice_generated: boolean
          is_sent_to_finance: boolean
          stage_name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number | null
          hubspot_pipeline_id: string
          hubspot_stage_id: string
          id?: string
          is_closed_lost?: boolean
          is_closed_won?: boolean
          is_customer_paid?: boolean
          is_invoice_generated?: boolean
          is_sent_to_finance?: boolean
          stage_name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number | null
          hubspot_pipeline_id?: string
          hubspot_stage_id?: string
          id?: string
          is_closed_lost?: boolean
          is_closed_won?: boolean
          is_customer_paid?: boolean
          is_invoice_generated?: boolean
          is_sent_to_finance?: boolean
          stage_name?: string
          updated_at?: string
        }
        Relationships: []
      }
      hubspot_pipelines: {
        Row: {
          created_at: string
          hubspot_pipeline_id: string
          id: string
          is_active: boolean
          last_synced_at: string | null
          pipeline_name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          hubspot_pipeline_id: string
          id?: string
          is_active?: boolean
          last_synced_at?: string | null
          pipeline_name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          hubspot_pipeline_id?: string
          id?: string
          is_active?: boolean
          last_synced_at?: string | null
          pipeline_name?: string
          updated_at?: string
        }
        Relationships: []
      }
      hubspot_record_changes: {
        Row: {
          affects_compensation: boolean
          created_at: string
          detected_at: string
          field_name: string
          hubspot_object_id: string
          id: string
          new_value: Json | null
          object_type: string
          old_value: Json | null
          related_hubspot_object_id: string | null
          requires_review: boolean
          review_notes: string | null
          review_status: string
          reviewed_at: string | null
          reviewed_by: string | null
          sync_run_id: string | null
        }
        Insert: {
          affects_compensation?: boolean
          created_at?: string
          detected_at?: string
          field_name: string
          hubspot_object_id: string
          id?: string
          new_value?: Json | null
          object_type: string
          old_value?: Json | null
          related_hubspot_object_id?: string | null
          requires_review?: boolean
          review_notes?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          sync_run_id?: string | null
        }
        Update: {
          affects_compensation?: boolean
          created_at?: string
          detected_at?: string
          field_name?: string
          hubspot_object_id?: string
          id?: string
          new_value?: Json | null
          object_type?: string
          old_value?: Json | null
          related_hubspot_object_id?: string | null
          requires_review?: boolean
          review_notes?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          sync_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hubspot_record_changes_sync_run_id_fkey"
            columns: ["sync_run_id"]
            isOneToOne: false
            referencedRelation: "hubspot_sync_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      hubspot_sync_runs: {
        Row: {
          changes_detected: number
          companies_created: number
          companies_received: number
          companies_updated: number
          completed_at: string | null
          created_at: string
          deals_created: number
          deals_received: number
          deals_updated: number
          details: Json
          error_message: string | null
          id: string
          initiated_by: string | null
          started_at: string
          status: string
          sync_type: string
        }
        Insert: {
          changes_detected?: number
          companies_created?: number
          companies_received?: number
          companies_updated?: number
          completed_at?: string | null
          created_at?: string
          deals_created?: number
          deals_received?: number
          deals_updated?: number
          details?: Json
          error_message?: string | null
          id?: string
          initiated_by?: string | null
          started_at?: string
          status?: string
          sync_type?: string
        }
        Update: {
          changes_detected?: number
          companies_created?: number
          companies_received?: number
          companies_updated?: number
          completed_at?: string | null
          created_at?: string
          deals_created?: number
          deals_received?: number
          deals_updated?: number
          details?: Json
          error_message?: string | null
          id?: string
          initiated_by?: string | null
          started_at?: string
          status?: string
          sync_type?: string
        }
        Relationships: []
      }
      job_roles: {
        Row: {
          created_at: string
          department: string | null
          description: string | null
          id: string
          is_active: boolean
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          department?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          department?: string | null
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      payroll_batches: {
        Row: {
          actual_payment_date: string | null
          batch_name: string
          batch_origin: string
          created_at: string
          created_by: string | null
          finalized_at: string | null
          finalized_by: string | null
          historical_payroll_reference: string | null
          id: string
          notes: string | null
          payment_method: string | null
          payment_reference: string | null
          payroll_period_end: string | null
          payroll_period_start: string | null
          scheduled_payment_date: string | null
          status: string
          updated_at: string
        }
        Insert: {
          actual_payment_date?: string | null
          batch_name: string
          batch_origin?: string
          created_at?: string
          created_by?: string | null
          finalized_at?: string | null
          finalized_by?: string | null
          historical_payroll_reference?: string | null
          id?: string
          notes?: string | null
          payment_method?: string | null
          payment_reference?: string | null
          payroll_period_end?: string | null
          payroll_period_start?: string | null
          scheduled_payment_date?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          actual_payment_date?: string | null
          batch_name?: string
          batch_origin?: string
          created_at?: string
          created_by?: string | null
          finalized_at?: string | null
          finalized_by?: string | null
          historical_payroll_reference?: string | null
          id?: string
          notes?: string | null
          payment_method?: string | null
          payment_reference?: string | null
          payroll_period_end?: string | null
          payroll_period_start?: string | null
          scheduled_payment_date?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_batches_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_batches_finalized_by_fkey"
            columns: ["finalized_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      payroll_payment_items: {
        Row: {
          amount_paid: number
          comp_earning_id: string
          created_at: string
          employee_id: string
          id: string
          payment_details: string | null
          payroll_batch_id: string
        }
        Insert: {
          amount_paid: number
          comp_earning_id: string
          created_at?: string
          employee_id: string
          id?: string
          payment_details?: string | null
          payroll_batch_id: string
        }
        Update: {
          amount_paid?: number
          comp_earning_id?: string
          created_at?: string
          employee_id?: string
          id?: string
          payment_details?: string | null
          payroll_batch_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_payment_items_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "payroll_payment_items_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_payment_items_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "payroll_payment_items_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_payment_items_payroll_batch_id_fkey"
            columns: ["payroll_batch_id"]
            isOneToOne: false
            referencedRelation: "payroll_batches"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          email: string
          employee_id: string | null
          full_name: string | null
          id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          employee_id?: string | null
          full_name?: string | null
          id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          employee_id?: string | null
          full_name?: string | null
          id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: true
            referencedRelation: "comp_deal_earning_candidates"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "profiles_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: true
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
        ]
      }
      reconciliation_actions: {
        Row: {
          action_at: string
          action_by: string | null
          action_reason: string
          claimed_amount: number | null
          comp_earning_id: string | null
          evidence: Json
          historical_comp_record_id: string | null
          id: string
          new_status: Database["public"]["Enums"]["reconciliation_status"]
          previous_status:
            | Database["public"]["Enums"]["reconciliation_status"]
            | null
          remaining_unpaid_amount: number | null
          verified_earned_amount: number | null
          verified_paid_amount: number | null
        }
        Insert: {
          action_at?: string
          action_by?: string | null
          action_reason: string
          claimed_amount?: number | null
          comp_earning_id?: string | null
          evidence?: Json
          historical_comp_record_id?: string | null
          id?: string
          new_status: Database["public"]["Enums"]["reconciliation_status"]
          previous_status?:
            | Database["public"]["Enums"]["reconciliation_status"]
            | null
          remaining_unpaid_amount?: number | null
          verified_earned_amount?: number | null
          verified_paid_amount?: number | null
        }
        Update: {
          action_at?: string
          action_by?: string | null
          action_reason?: string
          claimed_amount?: number | null
          comp_earning_id?: string | null
          evidence?: Json
          historical_comp_record_id?: string | null
          id?: string
          new_status?: Database["public"]["Enums"]["reconciliation_status"]
          previous_status?:
            | Database["public"]["Enums"]["reconciliation_status"]
            | null
          remaining_unpaid_amount?: number | null
          verified_earned_amount?: number | null
          verified_paid_amount?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "reconciliation_actions_action_by_fkey"
            columns: ["action_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reconciliation_actions_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_deal_earning_refresh_delta"
            referencedColumns: ["comp_earning_id"]
          },
          {
            foreignKeyName: "reconciliation_actions_comp_earning_id_fkey"
            columns: ["comp_earning_id"]
            isOneToOne: false
            referencedRelation: "comp_earnings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reconciliation_actions_historical_comp_record_id_fkey"
            columns: ["historical_comp_record_id"]
            isOneToOne: false
            referencedRelation: "historical_comp_records"
            referencedColumns: ["id"]
          },
        ]
      }
      revenue_classifications: {
        Row: {
          classification_code: string
          classification_name: string
          counts_toward_book: boolean
          created_at: string
          hubspot_deal_type_value: string
          id: string
          is_commissionable: boolean
          revenue_effect: string
          updated_at: string
        }
        Insert: {
          classification_code: string
          classification_name: string
          counts_toward_book?: boolean
          created_at?: string
          hubspot_deal_type_value: string
          id?: string
          is_commissionable?: boolean
          revenue_effect?: string
          updated_at?: string
        }
        Update: {
          classification_code?: string
          classification_name?: string
          counts_toward_book?: boolean
          created_at?: string
          hubspot_deal_type_value?: string
          id?: string
          is_commissionable?: boolean
          revenue_effect?: string
          updated_at?: string
        }
        Relationships: []
      }
      user_access_roles: {
        Row: {
          access_role: Database["public"]["Enums"]["access_role"]
          created_at: string
          effective_end_date: string | null
          effective_start_date: string
          id: string
          user_id: string
        }
        Insert: {
          access_role: Database["public"]["Enums"]["access_role"]
          created_at?: string
          effective_end_date?: string | null
          effective_start_date?: string
          id?: string
          user_id: string
        }
        Update: {
          access_role?: Database["public"]["Enums"]["access_role"]
          created_at?: string
          effective_end_date?: string | null
          effective_start_date?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_access_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      comp_deal_earning_candidates: {
        Row: {
          amount_label: string | null
          amount_source: string | null
          calculated_earning_amount: number | null
          calculation_status: string | null
          calculation_type: string | null
          candidate_key: string | null
          comp_plan_id: string | null
          company_cem_id: string | null
          company_name: string | null
          component_code: string | null
          component_configuration: Json | null
          component_rate: number | null
          credit_configuration: Json | null
          credit_method: string | null
          credit_percentage: number | null
          credit_review_status: string | null
          credit_rule_id: string | null
          deal_name: string | null
          deal_owner_id: string | null
          deal_rule_id: string | null
          earned_date: string | null
          eligibility_status: string | null
          eligible_date: string | null
          email: string | null
          employee_hubspot_owner_id: string | null
          employee_id: string | null
          full_name: string | null
          hubspot_company_id: string | null
          hubspot_deal_id: string | null
          hubspot_deal_type: string | null
          hubspot_pipeline_id: string | null
          hubspot_record_url: string | null
          hubspot_stage_id: string | null
          invoice_paid_date: string | null
          marks_earned: boolean | null
          marks_eligible: boolean | null
          marks_paid: boolean | null
          measurement_label: string | null
          measurement_source: string | null
          owner_cem_mismatch: boolean | null
          pipeline_name: string | null
          plan_assignment_id: string | null
          plan_component_id: string | null
          plan_component_name: string | null
          plan_name: string | null
          plan_status: string | null
          plan_version_id: string | null
          requires_credit_review: boolean | null
          source_amount: number | null
          stage_name: string | null
          stored_review_notes: string | null
          version_number: number | null
        }
        Relationships: []
      }
      comp_deal_earning_refresh_delta: {
        Row: {
          approved_amount: number | null
          calculation_status: string | null
          candidate_key: string | null
          change_type: string | null
          comp_earning_id: string | null
          company_name: string | null
          credit_review_status: string | null
          current_earned_amount: number | null
          current_earned_date: string | null
          current_eligibility_status: string | null
          current_eligible_amount: number | null
          current_eligible_date: string | null
          current_stage_name: string | null
          deal_name: string | null
          employee_id: string | null
          full_name: string | null
          hubspot_deal_id: string | null
          hubspot_record_url: string | null
          invoice_paid_date: string | null
          is_financially_protected: boolean | null
          manager_approval_status: string | null
          paid_amount: number | null
          payment_status: string | null
          plan_assignment_id: string | null
          plan_component_id: string | null
          plan_component_name: string | null
          previous_earned_amount: number | null
          previous_earned_date: string | null
          previous_eligibility_status: string | null
          previous_eligible_amount: number | null
          previous_eligible_date: string | null
          previous_stage_name: string | null
          requires_credit_review: boolean | null
          requires_review: boolean | null
        }
        Relationships: []
      }
      hubspot_compensation_deals: {
        Row: {
          average_arr: number | null
          close_date: string | null
          contract_end_date: string | null
          contract_start_date: string | null
          contract_term_label: string | null
          contract_term_months: number | null
          contract_term_years: number | null
          contract_url: string | null
          created_at: string | null
          deal_name: string | null
          first_year_arr: number | null
          hubspot_company_id: string | null
          hubspot_created_at: string | null
          hubspot_deal_id: string | null
          hubspot_deal_type: string | null
          hubspot_owner_id: string | null
          hubspot_pipeline_id: string | null
          hubspot_record_url: string | null
          hubspot_stage_id: string | null
          hubspot_updated_at: string | null
          id: string | null
          invoice_paid_date: string | null
          is_compensation_scope: boolean | null
          last_change_detected_at: string | null
          last_synced_at: string | null
          one_time_fee: number | null
          payment_frequency: string | null
          pipeline_name: string | null
          raw_hubspot_data: Json | null
          scope_reason: string | null
          source_fingerprint: string | null
          stage_name: string | null
          subscription_updated_date: string | null
          total_contract_value: number | null
          updated_at: string | null
        }
        Relationships: []
      }
      hubspot_deal_scope: {
        Row: {
          average_arr: number | null
          close_date: string | null
          contract_end_date: string | null
          contract_start_date: string | null
          contract_term_label: string | null
          contract_term_months: number | null
          contract_term_years: number | null
          contract_url: string | null
          created_at: string | null
          deal_name: string | null
          first_year_arr: number | null
          hubspot_company_id: string | null
          hubspot_created_at: string | null
          hubspot_deal_id: string | null
          hubspot_deal_type: string | null
          hubspot_owner_id: string | null
          hubspot_pipeline_id: string | null
          hubspot_record_url: string | null
          hubspot_stage_id: string | null
          hubspot_updated_at: string | null
          id: string | null
          invoice_paid_date: string | null
          is_compensation_scope: boolean | null
          last_change_detected_at: string | null
          last_synced_at: string | null
          one_time_fee: number | null
          payment_frequency: string | null
          pipeline_name: string | null
          raw_hubspot_data: Json | null
          scope_reason: string | null
          source_fingerprint: string | null
          stage_name: string | null
          subscription_updated_date: string | null
          total_contract_value: number | null
          updated_at: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      apply_comp_deal_earning_refresh: { Args: never; Returns: Json }
      get_compensation_dashboard_data: { Args: never; Returns: Json }
      refresh_hubspot_compensation_data: {
        Args: { force_refresh?: boolean }
        Returns: Json
      }
      sync_hubspot_companies: { Args: never; Returns: Json }
      sync_hubspot_deal_company_associations: { Args: never; Returns: Json }
      sync_hubspot_deals: { Args: never; Returns: Json }
    }
    Enums: {
      access_role: "employee" | "manager" | "approver" | "payroll" | "admin"
      adjustment_type:
        | "advance"
        | "draw"
        | "clawback"
        | "chargeback"
        | "manual_increase"
        | "manual_decrease"
        | "retroactive_rate_change"
        | "proration"
        | "correction"
      approval_status:
        | "not_required"
        | "pending"
        | "approved"
        | "rejected"
        | "returned"
      comp_period_status:
        | "open"
        | "calculating"
        | "employee_review"
        | "manager_review"
        | "approved"
        | "payroll_processing"
        | "closed"
      credit_method:
        | "deal_owner"
        | "all_qualifying_revenue"
        | "named_employee"
        | "split_credit"
        | "team"
        | "manual"
      earning_origin:
        | "system_calculated"
        | "historical_import"
        | "manual_entry"
        | "adjustment"
      eligibility_status:
        | "pending_condition"
        | "eligible"
        | "ineligible"
        | "expired"
        | "waived"
      payment_status:
        | "not_payable"
        | "ready_for_payroll"
        | "scheduled"
        | "partially_paid"
        | "paid"
        | "held"
      payout_timing_method: "annual" | "all_years_upfront"
      plan_version_status: "draft" | "active" | "retired"
      reconciliation_status:
        | "not_reviewed"
        | "matched"
        | "partially_matched"
        | "needs_information"
        | "confirmed_unpaid"
        | "confirmed_partially_paid"
        | "confirmed_paid"
        | "excluded"
        | "duplicate"
      source_match_status:
        | "not_attempted"
        | "suggested"
        | "confirmed"
        | "not_found"
        | "not_applicable"
      verification_status:
        | "not_ready"
        | "pending_employee"
        | "verified"
        | "correction_requested"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      access_role: ["employee", "manager", "approver", "payroll", "admin"],
      adjustment_type: [
        "advance",
        "draw",
        "clawback",
        "chargeback",
        "manual_increase",
        "manual_decrease",
        "retroactive_rate_change",
        "proration",
        "correction",
      ],
      approval_status: [
        "not_required",
        "pending",
        "approved",
        "rejected",
        "returned",
      ],
      comp_period_status: [
        "open",
        "calculating",
        "employee_review",
        "manager_review",
        "approved",
        "payroll_processing",
        "closed",
      ],
      credit_method: [
        "deal_owner",
        "all_qualifying_revenue",
        "named_employee",
        "split_credit",
        "team",
        "manual",
      ],
      earning_origin: [
        "system_calculated",
        "historical_import",
        "manual_entry",
        "adjustment",
      ],
      eligibility_status: [
        "pending_condition",
        "eligible",
        "ineligible",
        "expired",
        "waived",
      ],
      payment_status: [
        "not_payable",
        "ready_for_payroll",
        "scheduled",
        "partially_paid",
        "paid",
        "held",
      ],
      payout_timing_method: ["annual", "all_years_upfront"],
      plan_version_status: ["draft", "active", "retired"],
      reconciliation_status: [
        "not_reviewed",
        "matched",
        "partially_matched",
        "needs_information",
        "confirmed_unpaid",
        "confirmed_partially_paid",
        "confirmed_paid",
        "excluded",
        "duplicate",
      ],
      source_match_status: [
        "not_attempted",
        "suggested",
        "confirmed",
        "not_found",
        "not_applicable",
      ],
      verification_status: [
        "not_ready",
        "pending_employee",
        "verified",
        "correction_requested",
      ],
    },
  },
} as const
