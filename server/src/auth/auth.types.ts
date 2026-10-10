export interface AuthPrincipal {
  userId: string;
  organizationId: string;
  sessionId: string;
  permissionVersion: number;
}

declare global {
  namespace Express {
    interface Request {
      principal?: AuthPrincipal;
    }
  }
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  accessExpiresAt: string;
  sessionId: string;
}
