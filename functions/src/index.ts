// Cloud Functions entry point — every deployable function is exported here.
// Kept as a thin barrel file; each function's actual logic lives in its own
// module under src/, grouped by feature.

export { sendChatMessage } from "./chat/sendChatMessage";
export { onChatMessageCreated } from "./chat/rateLimitTrigger";
export { updateSkillLevelOnOrder } from "./chat/updateSkillLevelOnOrder";
export { aggregateCommunitySentiment } from "./sentiment/aggregateSentiment";
export { generateDailyPuzzle } from "./puzzle/generateDailyPuzzle";
export { submitPuzzleAnswer } from "./puzzle/submitPuzzleAnswer";
export { computeMarketWeather } from "./weather/computeMarketWeather";
export { computeCohortMedians } from "./cohorts/computeCohortMedians";
export { deleteAccount } from "./account/deleteAccount";
export { evaluateTradeMilestones } from "./certifications/evaluateTradeMilestones";
export { evaluateBacktestMilestones } from "./certifications/evaluateBacktestMilestones";
export { recordBacktestCompletion } from "./backtester/recordBacktestCompletion";
export { addTradeRationale } from "./rationale/addTradeRationale";
export {
  recomputeTraderStatsOnOrder,
  recomputeTraderStatsDaily,
} from "./traderProfile/recomputeTraderStats";
export { syncProfileVisibility } from "./traderProfile/syncProfileVisibility";
export { onFollowCreated, onFollowDeleted } from "./traderProfile/onFollowChange";
export { computeLeaderboard } from "./traderProfile/computeLeaderboard";
export {
  publicActivityOnTrade,
  publicActivityOnRationale,
  publicActivityOnCertification,
} from "./traderProfile/publicActivity";
export { checkPriceAlerts } from "./alerts/checkPriceAlerts";
export { checkConditionalOrders } from "./trading/checkConditionalOrders";
export { createOrgInviteCode, redeemOrgInviteCode } from "./growth/orgs";
export { computeOrgAggregateStats } from "./growth/computeOrgAggregateStats";
export { generateReferralCode, redeemReferralCode } from "./growth/referrals";
export { aggregateCryptoNews } from "./news/aggregateNews";
