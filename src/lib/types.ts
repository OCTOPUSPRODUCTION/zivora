export type GuideStatus = "draft" | "published";

export type Step = {
  id: string;
  guide_id: string;
  position: number;
  title: string;
  description: string;
  image_url: string | null;
  created_at?: string;
  updated_at?: string;
};

export type Guide = {
  id: string;
  user_id: string;
  title: string;
  description: string;
  status: GuideStatus;
  is_public: boolean;
  created_at: string;
  updated_at: string;
  steps?: Step[];
};
