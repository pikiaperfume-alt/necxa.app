export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      chat_rooms: {
        Row: {
          id: string
          property_id: string | null
          escrow_id: string | null
          agent_id: string
          client_id: string
          room_type: 'inquiry' | 'escrow_active' | 'support' | 'creator_dm'
          status: 'active' | 'locked' | 'archived'
          latest_message: string | null
          latest_message_at: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          property_id?: string | null
          escrow_id?: string | null
          agent_id: string
          client_id: string
          room_type: 'inquiry' | 'escrow_active' | 'support' | 'creator_dm'
          status?: 'active' | 'locked' | 'archived'
          latest_message?: string | null
          latest_message_at?: string
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['chat_rooms']['Insert']>
      }
      chat_messages: {
        Row: {
          id: string
          room_id: string
          sender_id: string
          message_type: 'text' | 'image' | 'system_escrow_deposit' | 'system_wallet_refund' | 'system_qr_scan' | 'location_pin'
          content: string | null
          media_url: string | null
          metadata: Json | null
          is_read: boolean
          read_at: string | null
          created_at: string
        }
        Insert: {
          id?: string
          room_id: string
          sender_id: string
          message_type?: 'text' | 'image' | 'system_escrow_deposit' | 'system_wallet_refund' | 'system_qr_scan' | 'location_pin'
          content?: string | null
          media_url?: string | null
          metadata?: Json | null
          is_read?: boolean
          read_at?: string | null
          created_at?: string
        }
        Update: Partial<Database['public']['Tables']['chat_messages']['Insert']>
      }
      creators: {
        Row: {
          id: string
          display_name: string | null
          bio: string | null
          content_niche: string
          total_followers: number
          total_likes: number
          is_live: boolean
          agora_channel_token: string | null
          tier: 'rising' | 'established' | 'titan'
          wallet_split_percentage: number
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          display_name?: string | null
          bio?: string | null
          content_niche?: string
          total_followers?: number
          total_likes?: number
          is_live?: boolean
          agora_channel_token?: string | null
          tier?: 'rising' | 'established' | 'titan'
          wallet_split_percentage?: number
          created_at?: string
          updated_at?: string
        }
        Update: Partial<Database['public']['Tables']['creators']['Insert']>
      }
      creator_followers: {
        Row: {
          id: string
          creator_id: string
          follower_id: string
          notification_level: 'all' | 'live_only' | 'none'
          created_at: string
        }
        Insert: {
          id?: string
          creator_id: string
          follower_id: string
          notification_level?: 'all' | 'live_only' | 'none'
          created_at?: string
        }
        Update: Partial<Database['public']['Tables']['creator_followers']['Insert']>
      }
      creator_broadcast_channels: {
        Row: {
          id: string
          creator_id: string
          channel_name: string | null
          is_subscriber_only: boolean
          created_at: string
        }
        Insert: {
          id?: string
          creator_id: string
          channel_name?: string | null
          is_subscriber_only?: boolean
          created_at?: string
        }
        Update: Partial<Database['public']['Tables']['creator_broadcast_channels']['Insert']>
      }
      creator_broadcast_messages: {
        Row: {
          id: string
          channel_id: string
          content: string | null
          media_url: string | null
          likes_count: number
          created_at: string
        }
        Insert: {
          id?: string
          channel_id: string
          content?: string | null
          media_url?: string | null
          likes_count?: number
          created_at?: string
        }
        Update: Partial<Database['public']['Tables']['creator_broadcast_messages']['Insert']>
      }
    }
  }
}
