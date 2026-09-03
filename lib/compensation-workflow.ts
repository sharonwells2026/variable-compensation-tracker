export type CompensationLifecycleStatus =
  | "earned"
  | "eligible"
  | "approved"
  | "paid";

export type OperationalWorkflowStatus =
  | "admin_review"
  | "pending_executive_approval"
  | "approved"
  | "pending_finance_acceptance"
  | "accepted_for_payment"
  | "paid";

export type WorkflowActor =
  | "employee"
  | "compensation_administrator"
  | "executive_approver"
  | "finance_payroll"
  | "system_administrator";

export type WorkflowStep = {
  key: OperationalWorkflowStatus;
  label: string;
  owner: WorkflowActor;
  description: string;
};

export const defaultCompensationWorkflow: WorkflowStep[] = [
  {
    key: "admin_review",
    label: "Compensation review",
    owner: "compensation_administrator",
    description:
      "Compensation Administrator validates the calculation, source data, eligibility evidence, overrides, and supporting detail before executive approval.",
  },
  {
    key: "pending_executive_approval",
    label: "Executive approval",
    owner: "executive_approver",
    description:
      "Executive Approver reviews the proposed payout and either approves it or returns it for correction.",
  },
  {
    key: "approved",
    label: "Approved",
    owner: "executive_approver",
    description:
      "Required compensation authorization is complete. Approval does not mean the payment has been processed.",
  },
  {
    key: "pending_finance_acceptance",
    label: "Finance acceptance",
    owner: "finance_payroll",
    description:
      "Finance reviews the approved obligation and accepts it for the payment process.",
  },
  {
    key: "accepted_for_payment",
    label: "Accepted for payment",
    owner: "finance_payroll",
    description:
      "Finance has accepted the approved payout for processing. The item is still not Paid until payment is confirmed.",
  },
  {
    key: "paid",
    label: "Paid",
    owner: "finance_payroll",
    description:
      "Finance records the actual payment date and reference. Paid history is preserved; corrections are made through adjustments rather than silent mutation.",
  },
];

const transitions: Record<OperationalWorkflowStatus, OperationalWorkflowStatus[]> = {
  admin_review: ["pending_executive_approval"],
  pending_executive_approval: ["approved", "admin_review"],
  approved: ["pending_finance_acceptance", "admin_review"],
  pending_finance_acceptance: ["accepted_for_payment", "admin_review"],
  accepted_for_payment: ["paid", "admin_review"],
  paid: [],
};

export function canTransitionWorkflow(
  from: OperationalWorkflowStatus,
  to: OperationalWorkflowStatus,
  actor: WorkflowActor,
): boolean {
  if (actor === "system_administrator") return from !== "paid" || to === "paid";
  if (!transitions[from].includes(to)) return false;

  if (from === "admin_review") return actor === "compensation_administrator";
  if (from === "pending_executive_approval") return actor === "executive_approver";
  if (from === "approved") return actor === "finance_payroll";
  if (from === "pending_finance_acceptance") return actor === "finance_payroll";
  if (from === "accepted_for_payment") return actor === "finance_payroll";
  return false;
}

export function workflowLabel(status: OperationalWorkflowStatus): string {
  return defaultCompensationWorkflow.find((step) => step.key === status)?.label ?? status;
}

export const currentEngagifiiWorkflow = {
  compensationAdministrator: "Sharon Wells",
  executiveApprover: "Namit Bhatia",
  financePayroll: "Scott Key",
  employeeExample: "Wes Morris",
  employeeSequence: [
    "Employee verifies/submits",
    "Sharon reviews",
    "Namit approves",
    "Scott accepts for payment",
    "Scott confirms payment",
  ],
  sharonSequence: [
    "Sharon administers/submits",
    "Namit approves",
    "Scott accepts for payment",
    "Scott confirms payment",
  ],
} as const;

export function lifecycleFromOperationalStatus(
  operationalStatus: OperationalWorkflowStatus,
  isEarned: boolean,
  isEligible: boolean,
): CompensationLifecycleStatus | null {
  if (operationalStatus === "paid") return "paid";
  if (
    operationalStatus === "approved" ||
    operationalStatus === "pending_finance_acceptance" ||
    operationalStatus === "accepted_for_payment"
  ) {
    return "approved";
  }
  if (isEligible) return "eligible";
  if (isEarned) return "earned";
  return null;
}
