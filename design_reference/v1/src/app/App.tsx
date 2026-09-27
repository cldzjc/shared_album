import React, { useState, useEffect } from "react";
import { BrowserRouter, Routes, Route, useNavigate, useLocation } from "react-router";
import { motion, AnimatePresence } from "motion/react";
import {
  User,
  Image as ImageIcon,
  Lock,
  ArrowRight,
  ChevronLeft,
  Plus,
  RefreshCw,
  Trash2,
  Download,
  AlertCircle,
  X,
  Upload,
  CheckCircle2,
  Clock,
  ImageOff,
  FolderHeart
} from "lucide-react";

// --- Mock Data & State Management ---
type AccountType = "guest" | "normal";

interface UserProfile {
  id: string;
  name: string;
  accountType: AccountType;
}

interface Album {
  id: string;
  name: string;
  shareCode: string;
  role: "creator" | "member";
  expiresAt: Date;
}

interface Photo {
  id: string;
  url: string;
  uploadedBy: string;
  uploadedAt: Date;
  status: "success" | "uploading" | "error";
  progress?: number;
}

// Global mocked state for the prototype
let globalUser: UserProfile = { id: "u1", name: "Chen Ming", accountType: "guest" };
let globalAlbums: Album[] = [
  { id: "a1", name: "Weekend Trip", shareCode: "123456", role: "member", expiresAt: new Date(Date.now() + 86400000) }
];
let globalPhotos: Record<string, Photo[]> = {
  "a1": [
    { id: "p1", url: "https://images.unsplash.com/photo-1682687220742-aba13b6e50ba?w=400&h=400&fit=crop", uploadedBy: "u2", uploadedAt: new Date(), status: "success" },
    { id: "p2", url: "https://images.unsplash.com/photo-1682687982501-1e58f813f22b?w=400&h=400&fit=crop", uploadedBy: "u1", uploadedAt: new Date(), status: "success" },
  ]
};

// --- Design System Components (Apple HIG Inspired) ---

const Button = ({ children, variant = "primary", className = "", ...props }: any) => {
  const baseStyle = "w-full rounded-[14px] font-semibold text-[17px] text-center transition-all active:scale-[0.98] disabled:opacity-50 flex items-center justify-center gap-2 py-3.5";
  const variants = {
    primary: "bg-primary text-primary-foreground",
    secondary: "bg-secondary text-secondary-foreground",
    outline: "border-[1.5px] border-border text-foreground bg-card",
    ghost: "bg-transparent text-primary",
    danger: "bg-[#FF3B30] text-white"
  };
  return (
    <button className={`${baseStyle} ${variants[variant as keyof typeof variants]} ${className}`} {...props}>
      {children}
    </button>
  );
};

const Input = ({ label, icon: Icon, error, ...props }: any) => {
  return (
    <div className="w-full flex flex-col gap-1.5">
      {label && <label className="text-[13px] font-medium text-muted-foreground ml-1 uppercase tracking-wider">{label}</label>}
      <div className={`relative flex items-center w-full rounded-[14px] bg-card overflow-hidden transition-all ${error ? 'border border-[#FF3B30]' : ''}`}>
        {Icon && <div className="pl-4 text-muted-foreground"><Icon size={20} /></div>}
        <input 
          className="w-full bg-transparent outline-none py-4 px-4 text-[17px] text-foreground placeholder:text-muted-foreground/50" 
          {...props} 
        />
      </div>
      {error && <span className="text-xs text-[#FF3B30] ml-1">{error}</span>}
    </div>
  );
};

const Card = ({ children, className = "", onClick }: any) => {
  return (
    <div 
      onClick={onClick}
      className={`bg-card rounded-[20px] p-5 ${onClick ? 'cursor-pointer active:opacity-70 transition-opacity' : ''} ${className}`}
    >
      {children}
    </div>
  );
};

const SnackBar = ({ message, type = "success", onClose }: any) => {
  useEffect(() => {
    const t = setTimeout(onClose, 3000);
    return () => clearTimeout(t);
  }, [onClose]);
  
  return (
    <motion.div 
      initial={{ opacity: 0, y: 20, scale: 0.95 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, y: 10, scale: 0.95 }}
      className={`fixed top-12 left-1/2 -translate-x-1/2 z-50 px-6 py-3.5 rounded-full flex items-center gap-2 shadow-[0_8px_30px_rgba(0,0,0,0.12)] text-white font-medium whitespace-nowrap`}
      style={{ backgroundColor: type === "success" ? "#34C759" : "#FF3B30" }}
    >
      {type === "success" ? <CheckCircle2 size={18} /> : <AlertCircle size={18} />}
      {message}
    </motion.div>
  );
};

const Dialog = ({ isOpen, title, description, confirmText = "Confirm", cancelText = "Cancel", onConfirm, onCancel, confirmVariant="primary" }: any) => {
  if (!isOpen) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-5 bg-black/20 backdrop-blur-md">
      <motion.div 
        initial={{ opacity: 0, scale: 0.95, y: 10 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.95, y: 10 }}
        transition={{ type: "spring", damping: 25, stiffness: 300 }}
        className="bg-card/90 backdrop-blur-xl w-full max-w-sm rounded-[24px] p-6 shadow-2xl flex flex-col items-center text-center"
      >
        <h3 className="text-[20px] font-bold text-foreground mb-2">{title}</h3>
        {description && <p className="text-[15px] text-muted-foreground mb-6 leading-relaxed">{description}</p>}
        <div className="w-full flex flex-col gap-3">
          <Button variant={confirmVariant} onClick={onConfirm}>{confirmText}</Button>
          <Button variant="secondary" onClick={onCancel}>{cancelText}</Button>
        </div>
      </motion.div>
    </div>
  );
};

const PageTransition = ({ children, className = "" }: any) => {
  return (
    <motion.div
      initial={{ opacity: 0, x: 10 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: -10 }}
      transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
      className={`min-h-screen w-full bg-background pb-24 ${className}`}
    >
      {children}
    </motion.div>
  );
};

// --- Helper Functions ---
const getGreeting = () => {
  const hour = new Date().getHours();
  if (hour < 12) return "早上好";
  if (hour < 18) return "下午好";
  return "晚上好";
};

// --- Pages ---

function Home() {
  const navigate = useNavigate();
  const [user, setUser] = useState(globalUser);
  const [showUpgradeModal, setShowUpgradeModal] = useState(false);

  const handleCreateClick = () => {
    if (user.accountType === "guest") {
      setShowUpgradeModal(true);
    } else {
      navigate("/create");
    }
  };

  const getSubGreeting = () => {
    if (user.accountType === "guest") return "输入好友分享码即可查看共享相册。";
    if (globalAlbums.length === 0) return "创建你的第一个共享相册。";
    return "继续记录属于你们的回忆。";
  };

  return (
    <PageTransition className="pt-16 px-5 max-w-md mx-auto">
      {/* Apple-style Greeting Header */}
      <div className="mb-10">
        <h1 className="text-[34px] font-bold text-foreground tracking-tight leading-tight mb-2">
          {getGreeting()}，<br/>
          {user.name}
        </h1>
        <p className="text-[17px] text-muted-foreground">{getSubGreeting()}</p>
      </div>

      {/* Identity Card */}
      <div className="mb-8">
        <h2 className="text-[13px] font-semibold text-muted-foreground uppercase tracking-wider mb-2 ml-4">账户状态</h2>
        <Card className="flex items-center justify-between py-4">
          <div className="flex items-center gap-4">
            <div className={`w-12 h-12 rounded-full flex items-center justify-center ${user.accountType === "guest" ? 'bg-secondary' : 'bg-[#34C759]/10'}`}>
              {user.accountType === "guest" ? <User size={24} className="text-muted-foreground" /> : <CheckCircle2 size={24} className="text-[#34C759]" />}
            </div>
            <div>
              <div className="font-semibold text-[17px] text-foreground mb-0.5">{user.accountType === "guest" ? "游客身份" : "正式账号"}</div>
              <div className="text-[13px] text-muted-foreground">
                {user.accountType === "guest" ? "升级身份解锁更多功能" : "已升级为正式账号"}
              </div>
            </div>
          </div>
          {user.accountType === "guest" ? (
            <button 
              onClick={() => navigate("/login")} 
              className="text-[15px] font-semibold text-primary bg-secondary px-4 py-2 rounded-full active:opacity-70 transition-opacity"
            >
              升级身份
            </button>
          ) : (
            <button 
              onClick={() => {
                globalUser = { id: "u1", name: "Guest", accountType: "guest" };
                setUser(globalUser);
              }} 
              className="text-[15px] font-semibold text-muted-foreground active:opacity-70 transition-opacity"
            >
              退出
            </button>
          )}
        </Card>
      </div>

      {/* Albums List */}
      <div className="mb-6 flex items-center justify-between ml-4 mr-4">
        <h2 className="text-[13px] font-semibold text-muted-foreground uppercase tracking-wider">我的相册</h2>
        {globalAlbums.length > 0 && (
          <span className="text-[13px] font-medium text-muted-foreground">{globalAlbums.length} 个</span>
        )}
      </div>

      {globalAlbums.length === 0 ? (
        <Card className="py-12 flex flex-col items-center text-center shadow-none bg-transparent border-2 border-dashed border-border/50">
          <div className="w-16 h-16 bg-card rounded-full flex items-center justify-center mb-4 text-muted-foreground shadow-sm">
            <FolderHeart size={28} />
          </div>
          <h3 className="font-semibold text-foreground mb-1 text-[17px]">还没有参与过任何相册</h3>
          <p className="text-[15px] text-muted-foreground">点击下方按钮创建或加入相册</p>
        </Card>
      ) : (
        <div className="bg-card rounded-[20px] overflow-hidden">
          {globalAlbums.map((album, index) => (
            <div key={album.id}>
              <div 
                onClick={() => navigate(`/album/${album.id}`)}
                className="flex items-center p-4 active:bg-secondary/50 transition-colors cursor-pointer"
              >
                <div className="w-12 h-12 rounded-[12px] bg-secondary flex items-center justify-center text-muted-foreground flex-shrink-0">
                  <ImageIcon size={24} />
                </div>
                <div className="ml-4 flex-1 min-w-0">
                  <h3 className="font-semibold text-foreground truncate text-[17px]">{album.name}</h3>
                  <div className="flex items-center gap-2 text-[14px] mt-0.5">
                    <span className="text-muted-foreground font-mono">{album.shareCode}</span>
                    <span className="w-1 h-1 bg-border rounded-full"></span>
                    <span className="text-muted-foreground">
                      {album.role === 'creator' ? '创建者' : '参与者'}
                    </span>
                  </div>
                </div>
                <ChevronLeft size={20} className="text-muted-foreground/40 rotate-180 ml-2" />
              </div>
              {index < globalAlbums.length - 1 && <div className="h-[1px] bg-border ml-[76px]"></div>}
            </div>
          ))}
        </div>
      )}

      {/* Floating Action Buttons */}
      <div className="fixed bottom-0 left-0 right-0 p-6 bg-gradient-to-t from-background via-background/90 to-transparent pointer-events-none pb-8">
        <div className="max-w-md mx-auto flex flex-col gap-3 pointer-events-auto">
          <Button onClick={handleCreateClick}>创建相册</Button>
          <Button variant="outline" onClick={() => navigate("/join")} className="bg-card/80 backdrop-blur-xl">加入相册</Button>
        </div>
      </div>

      {/* Corrected Dialog text, unified terminology */}
      <Dialog 
        isOpen={showUpgradeModal} 
        title="需要升级身份" 
        description="升级身份后，即可创建共享相册，并上传、下载和管理照片。"
        confirmText="升级身份"
        onConfirm={() => navigate("/login")}
        onCancel={() => setShowUpgradeModal(false)}
      />
    </PageTransition>
  );
}

function Login() {
  const navigate = useNavigate();
  const [isLoginMode, setIsLoginMode] = useState(false);
  const [loading, setLoading] = useState(false);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setTimeout(() => {
      globalUser = { id: "u2", name: "Chen Ming", accountType: "normal" };
      setLoading(false);
      navigate(-1);
    }, 800);
  };

  return (
    <PageTransition className="flex flex-col items-center justify-center px-5 relative pt-12">
      <div className="w-full flex items-center justify-between mb-8 absolute top-0 left-0 right-0 p-4">
        <button onClick={() => navigate(-1)} className="text-primary font-medium text-[17px] active:opacity-70 px-2 py-1">
          取消
        </button>
      </div>

      <div className="w-full max-w-sm flex flex-col items-center text-center mt-12">
        <div className="w-20 h-20 bg-card rounded-[22px] flex items-center justify-center text-primary mb-6 shadow-sm">
          {isLoginMode ? <Lock size={36} /> : <User size={36} />}
        </div>
        <h2 className="text-[28px] font-bold mb-3 tracking-tight">
          {isLoginMode ? "升级身份" : "升级身份"}
        </h2>
        <p className="text-[17px] text-muted-foreground mb-10 px-2 leading-relaxed">
          升级身份后，即可创建共享相册，<br/>并上传、下载和管理照片。
        </p>

        <form onSubmit={handleSubmit} className="w-full flex flex-col gap-4 mb-8">
          <div className="bg-card rounded-[14px] overflow-hidden flex flex-col">
            {!isLoginMode && (
              <>
                <input placeholder="昵称" defaultValue={globalUser.name} className="w-full bg-transparent outline-none py-4 px-5 text-[17px] text-foreground placeholder:text-muted-foreground/50 border-b border-border" />
              </>
            )}
            <input placeholder="邮箱地址" type="email" required className="w-full bg-transparent outline-none py-4 px-5 text-[17px] text-foreground placeholder:text-muted-foreground/50 border-b border-border" />
            <input placeholder="密码" type="password" required className="w-full bg-transparent outline-none py-4 px-5 text-[17px] text-foreground placeholder:text-muted-foreground/50" />
          </div>

          <Button type="submit" className="mt-4" disabled={loading}>
            {loading ? "处理中..." : "升级身份"}
          </Button>
        </form>

        <button 
          onClick={() => setIsLoginMode(!isLoginMode)}
          className="text-[15px] font-medium text-muted-foreground hover:text-foreground transition-colors"
        >
          {isLoginMode ? "新用户？切换到注册" : "已有账号？切换到登录"}
        </button>
      </div>
    </PageTransition>
  );
}

function Create() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);

  if (globalUser.accountType === "guest") {
    return (
      <PageTransition className="flex flex-col items-center justify-center px-5 p-12 text-center h-screen">
        <div className="w-20 h-20 bg-card shadow-sm rounded-[22px] flex items-center justify-center text-primary mb-6">
          <Lock size={40} />
        </div>
        <h2 className="text-[28px] font-bold mb-3 tracking-tight">需要升级身份</h2>
        <p className="text-muted-foreground mb-10 text-[17px] leading-relaxed">升级身份后，即可创建共享相册，<br/>并上传、下载和管理照片。</p>
        <div className="w-full max-w-sm flex flex-col gap-3">
          <Button onClick={() => navigate("/login", { replace: true })}>升级身份</Button>
          <Button variant="secondary" onClick={() => navigate(-1)}>返回</Button>
        </div>
      </PageTransition>
    );
  }

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setTimeout(() => {
      const newAlbum: Album = {
        id: "a" + Date.now(),
        name: "新相册",
        shareCode: Math.floor(100000 + Math.random() * 900000).toString(),
        role: "creator",
        expiresAt: new Date(Date.now() + 86400000)
      };
      globalAlbums.unshift(newAlbum);
      setLoading(false);
      navigate("/");
    }, 800);
  };

  return (
    <PageTransition className="px-5 pt-4 max-w-md mx-auto relative bg-background">
      <div className="flex items-center justify-between mb-6">
        <button onClick={() => navigate(-1)} className="text-primary font-medium text-[17px] px-2 py-2 -ml-2 active:opacity-70">
          取消
        </button>
        <h1 className="text-[17px] font-bold">创建相册</h1>
        <div className="w-10"></div>
      </div>

      <div className="bg-card rounded-[20px] p-8 flex flex-col items-center text-center mb-8">
        <span className="text-[13px] font-semibold tracking-wider text-muted-foreground uppercase mb-3">专属分享码</span>
        <div className="text-[44px] font-bold tracking-[0.15em] text-foreground leading-none font-mono">
          782194
        </div>
      </div>

      <form onSubmit={handleCreate} className="flex flex-col gap-6">
        <div className="flex flex-col gap-4">
          <Input label="创建者昵称" defaultValue={globalUser.name} />
          <Input label="相册名称" placeholder="给相册起个名字" required />
          <Input label="访问密码 (可选)" placeholder="设置相册访问密码" type="password" />
        </div>
        
        <div className="flex items-start gap-3 mt-2 px-2">
          <Clock size={20} className="text-muted-foreground flex-shrink-0 mt-0.5" />
          <p className="text-[14px] text-muted-foreground leading-relaxed">
            相册将在创建 24 小时后自动销毁。<br/>到期后所有数据将被永久清除。
          </p>
        </div>

        <div className="fixed bottom-0 left-0 right-0 p-6 bg-gradient-to-t from-background via-background/90 to-transparent pb-8">
          <Button type="submit" disabled={loading}>
            {loading ? "创建中..." : "确认创建"}
          </Button>
        </div>
      </form>
    </PageTransition>
  );
}

function Join() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [snackbar, setSnackbar] = useState<any>(null);

  const handleJoin = (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setTimeout(() => {
      setLoading(false);
      setSnackbar({ message: "加入成功" });
      setTimeout(() => navigate("/album/a1", { replace: true }), 1000);
    }, 1000);
  };

  return (
    <PageTransition className="px-5 pt-4 max-w-md mx-auto relative bg-background">
      <div className="flex items-center justify-between mb-8">
        <button onClick={() => navigate(-1)} className="text-primary font-medium text-[17px] px-2 py-2 -ml-2 active:opacity-70">
          取消
        </button>
        <h1 className="text-[17px] font-bold">加入相册</h1>
        <div className="w-10"></div>
      </div>

      <div className="mb-8 px-2 text-center">
        <p className="text-[17px] text-muted-foreground leading-relaxed">
          请输入好友分享的 6 位数字分享码，<br/>以及对应的访问密码
        </p>
      </div>

      <form onSubmit={handleJoin} className="flex flex-col gap-6">
        <div className="flex flex-col gap-4">
          <Input placeholder="分享码 (6位数字)" type="number" maxLength={6} required className="font-mono text-center text-[22px] tracking-[0.2em]" />
          <Input placeholder="访问密码 (可选)" type="password" className="text-center" />
        </div>
        
        <div className="fixed bottom-0 left-0 right-0 p-6 bg-gradient-to-t from-background via-background/90 to-transparent pb-8">
          <Button type="submit" disabled={loading}>
            {loading ? "验证中..." : "加入相册"}
          </Button>
        </div>
      </form>
      {snackbar && <SnackBar {...snackbar} onClose={() => setSnackbar(null)} />}
    </PageTransition>
  );
}

function AlbumCountdownWidget({ expiresAt }: { expiresAt: Date }) {
  const [timeLeft, setTimeLeft] = useState("");
  const [isExpired, setIsExpired] = useState(false);

  useEffect(() => {
    const timer = setInterval(() => {
      const now = new Date().getTime();
      const distance = expiresAt.getTime() - now;

      if (distance < 0) {
        setIsExpired(true);
        setTimeLeft("已过期");
        clearInterval(timer);
      } else {
        const hours = Math.floor(distance / (1000 * 60 * 60));
        const minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60));
        setTimeLeft(`🕒 ${hours}h${minutes}m 后自动销毁`);
      }
    }, 1000);
    return () => clearInterval(timer);
  }, [expiresAt]);

  if (isExpired) {
    return <span className="text-[#FF3B30] font-medium">已过期</span>;
  }
  return <span className="text-muted-foreground font-medium whitespace-nowrap">{timeLeft}</span>;
}

function AlbumDetail() {
  const navigate = useNavigate();
  const location = useLocation();
  const albumId = location.pathname.split("/").pop() || "a1";
  const album = globalAlbums.find(a => a.id === albumId) || globalAlbums[0];
  const [photos, setPhotos] = useState<Photo[]>(globalPhotos[albumId] || []);
  const [previewPhoto, setPreviewPhoto] = useState<Photo | null>(null);
  const [showUpgradeModal, setShowUpgradeModal] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [isUploading, setIsUploading] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [snackbar, setSnackbar] = useState<any>(null);

  const handleUploadClick = () => {
    if (globalUser.accountType === "guest") {
      setShowUpgradeModal(true);
      return;
    }
    // Mock upload
    setIsUploading(true);
    setUploadProgress(10);
    const mockInterval = setInterval(() => {
      setUploadProgress(prev => {
        if (prev >= 100) {
          clearInterval(mockInterval);
          setIsUploading(false);
          const newPhoto: Photo = {
            id: "p" + Date.now(),
            url: "https://images.unsplash.com/photo-1682687221038-404670f09439?w=400&h=400&fit=crop",
            uploadedBy: globalUser.id,
            uploadedAt: new Date(),
            status: "success"
          };
          setPhotos([newPhoto, ...photos]);
          return 0;
        }
        return prev + 15;
      });
    }, 300);
  };

  const handleDelete = () => {
    if (previewPhoto) {
      setPhotos(photos.filter(p => p.id !== previewPhoto.id));
      setPreviewPhoto(null);
      setShowDeleteConfirm(false);
    }
  };

  return (
    <div className="min-h-screen bg-card pb-32">
      <div className="sticky top-0 z-10 bg-card/80 backdrop-blur-xl border-b border-border/50 px-4 py-3 flex items-center justify-between">
        <div className="flex items-center gap-2 overflow-hidden">
          <button onClick={() => navigate(-1)} className="w-10 h-10 flex-shrink-0 flex items-center justify-center -ml-2 text-primary active:opacity-70">
            <ChevronLeft size={28} />
          </button>
          <div className="flex flex-col overflow-hidden pt-0.5">
            <h1 className="font-bold text-foreground text-[17px] truncate leading-tight">{album.name}</h1>
            <div className="flex items-center gap-2 text-[12px] mt-0.5">
              <span className="font-mono text-muted-foreground">{album.shareCode}</span>
              <span className="text-border">•</span>
              <AlbumCountdownWidget expiresAt={album.expiresAt} />
            </div>
          </div>
        </div>
      </div>

      <div className="p-0.5">
        {photos.length === 0 && !isUploading ? (
          <div className="py-32 flex flex-col items-center text-center px-6">
            <div className="w-20 h-20 bg-secondary rounded-full flex items-center justify-center mb-6 text-muted-foreground/50">
              <ImageOff size={32} />
            </div>
            <h3 className="text-[20px] font-bold text-foreground mb-2">相册里空空如也</h3>
            <p className="text-[15px] text-muted-foreground">快点击下方按钮，分享第一张照片吧</p>
          </div>
        ) : (
          <div className="grid grid-cols-3 gap-0.5">
            {isUploading && (
              <div className="aspect-square bg-secondary flex flex-col items-center justify-center relative overflow-hidden">
                <Upload size={24} className="text-muted-foreground mb-2 animate-bounce" />
                <span className="text-[11px] font-bold text-muted-foreground">{uploadProgress}%</span>
                <div className="absolute bottom-0 left-0 h-1 bg-primary transition-all duration-300" style={{ width: `${uploadProgress}%` }} />
              </div>
            )}
            {photos.map(photo => (
              <div 
                key={photo.id} 
                className="aspect-square bg-secondary relative cursor-pointer active:opacity-80 transition-opacity"
                onClick={() => setPreviewPhoto(photo)}
              >
                <img src={photo.url} className="w-full h-full object-cover" alt="" />
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="fixed bottom-8 right-6 z-20">
        <button 
          onClick={handleUploadClick}
          disabled={isUploading}
          className={`h-[56px] rounded-full bg-primary text-primary-foreground shadow-[0_8px_20px_rgba(0,0,0,0.15)] flex items-center justify-center px-6 transition-all active:scale-[0.96] ${isUploading ? 'opacity-90 px-8' : 'w-[56px] px-0'}`}
        >
          {isUploading ? (
            <span className="font-bold text-[15px]">上传中 {uploadProgress}%</span>
          ) : (
            <Plus size={28} />
          )}
        </button>
      </div>

      {/* Fullscreen Photo Viewer */}
      <AnimatePresence>
        {previewPhoto && (
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 bg-black flex flex-col touch-none"
          >
            <div className="bg-gradient-to-b from-black/60 to-transparent p-4 flex items-center justify-between absolute top-0 left-0 right-0 z-10 pt-12">
              <div className="flex flex-col text-white px-2">
                <span className="text-[15px] font-medium opacity-90 truncate max-w-[200px]">{previewPhoto.id}.jpg</span>
                <span className="text-[13px] opacity-60">刚刚</span>
              </div>
              <button 
                onClick={() => setPreviewPhoto(null)}
                className="w-10 h-10 rounded-full bg-white/10 flex items-center justify-center text-white active:bg-white/20 backdrop-blur-md"
              >
                <X size={24} />
              </button>
            </div>
            
            <div className="flex-1 flex items-center justify-center overflow-hidden">
              <motion.img 
                layoutId={`img-${previewPhoto.id}`}
                src={previewPhoto.url} 
                className="w-full max-h-full object-contain" 
                alt="" 
              />
            </div>

            <div className="bg-gradient-to-t from-black/80 to-transparent p-6 pb-12 flex flex-col gap-4 absolute bottom-0 left-0 right-0 z-10">
              <button 
                onClick={() => {
                  if (globalUser.accountType === "guest") setShowUpgradeModal(true);
                  else setSnackbar({ message: "照片已保存到相册" });
                }}
                className="w-full h-14 bg-white/10 backdrop-blur-xl rounded-[16px] flex items-center justify-center gap-2 text-white font-semibold text-[17px] active:bg-white/20 transition-colors"
              >
                <Download size={20} />
                保存照片
              </button>
              
              {(globalUser.id === previewPhoto.uploadedBy || album.role === "creator") && (
                <button 
                  onClick={() => setShowDeleteConfirm(true)}
                  className="w-full h-14 bg-transparent rounded-[16px] flex items-center justify-center gap-2 text-[#FF453A] font-semibold text-[17px] active:bg-white/5 transition-colors"
                >
                  <Trash2 size={20} />
                  删除照片
                </button>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <Dialog 
        isOpen={showUpgradeModal} 
        title="需要升级身份" 
        description="升级身份后，即可创建共享相册，并上传、下载和管理照片。"
        confirmText="升级身份"
        onConfirm={() => {
          setShowUpgradeModal(false);
          setPreviewPhoto(null);
          navigate("/login");
        }}
        onCancel={() => setShowUpgradeModal(false)}
      />

      <Dialog 
        isOpen={showDeleteConfirm} 
        title="删除照片" 
        description="该操作无法撤销，确定要删除这张照片吗？"
        confirmText="删除"
        confirmVariant="danger"
        onConfirm={handleDelete}
        onCancel={() => setShowDeleteConfirm(false)}
      />

      {snackbar && <SnackBar {...snackbar} onClose={() => setSnackbar(null)} />}
    </div>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AnimatePresence mode="wait">
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/login" element={<Login />} />
          <Route path="/create" element={<Create />} />
          <Route path="/join" element={<Join />} />
          <Route path="/album/:id" element={<AlbumDetail />} />
        </Routes>
      </AnimatePresence>
    </BrowserRouter>
  );
}
