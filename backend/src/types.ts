export interface Env {
  DB: D1Database;
  ATTACHMENTS: R2Bucket;
  JWT_SECRET: string;
}

export interface UserPayload {
  id: string;
  email: string;
  role: 'admin' | 'employee';
}

export interface Profile {
  id: string;
  email: string;
  password_hash?: string;
  full_name: string;
  role: 'admin' | 'employee';
  is_active: number;
  approval_status: 'pending' | 'approved' | 'suspended';
  can_add: number;
  can_edit: number;
  can_delete: number;
  can_view: number;
  license_start_at?: string;
  license_end_at?: string;
  license_paused: number;
  license_paused_seconds_left?: number;
  last_paused_at?: string;
  activated_code?: string;
  phone_number?: string;
  birth_date?: string;
  avatar_path?: string;
  locked_until?: string | null;
  created_at: string;
}

export interface Permit {
  id: string;
  permit_number: number;
  permit_year: number;
  full_name: string;
  plot_number: string;
  permit_date: string;
  notes?: string;
  permit_type?: string;
  name_change_notes?: string;
  plot_area?: number;
  building_area?: number;
  name_per_new_registry?: string;
  attachment_urls: string;
  is_deleted: number;
  duplicate_flag: number;
  created_by?: string;
  created_at: string;
  updated_by?: string;
  updated_at: string;
}

