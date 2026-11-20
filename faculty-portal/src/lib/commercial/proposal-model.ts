import { z } from "zod";
import { plans } from "../../components/marketing/story-model";

const cleanText = (min: number, max: number) => z.string().trim().min(min).max(max)
  .refine(value => !/[\u0000-\u001f\u007f]/.test(value), "Remove unsupported control characters.");

export const proposalSchema = z.object({
  institution: cleanText(2, 100),
  contact: z.email().max(120),
  contactName: cleanText(0, 60).default(""),
  address: cleanText(0, 180).default(""),
  requirements: cleanText(0, 240).default(""),
  plan: z.enum(["core", "institution", "enterprise"]),
  students: z.number().int().min(100).max(100000),
}).strict();

export type ProposalInput = z.infer<typeof proposalSchema>;

export function proposalPrice(input: ProposalInput) {
  const plan = plans.find(item => item.id === input.plan);
  return { name: plan?.name ?? "Enterprise", rate: plan?.rate ?? null,
    subtotal: plan ? plan.rate * input.students : null };
}
