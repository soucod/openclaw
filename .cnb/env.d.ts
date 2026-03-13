declare namespace NodeJS {
    interface ProcessEnv {
        CNB_API_ENDPOINT?: string;
        CNB_WEB_ENDPOINT?: string;
        CNB_TOKEN?: string;
        CNB_REPO_SLUG?: string;
        CNB_ISSUE_IID?: string;
        CNB_PULL_REQUEST_IID?: string;
        CNB_COMMENT_BODY?: string;
        CNB_NPC_NAME?: string;
        CNB_NPC_PROMPT?: string;
        CNB_NPC_SLUG?: string;
        CNB_USER_TYPE?: string;
        CNB_USER_NAME?: string;
        CNB_USER_NICKNAME?: string;
    }
}
