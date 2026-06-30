import { useState, useEffect } from 'react';

interface DobaseThread {
  id: string;
  lastMessage: string;
  deepLink: string;
  updatedAt: string;
}

interface DobaseDocument {
  id: string;
  title: string;
  deepLink: string;
  updatedAt: string;
}

interface DobaseFile {
  id: string;
  filename: string;
  mimeType: string;
  size: number;
  deepLink: string;
}

interface DobaseSidebarProps {
  recordId: string;
  personEmail?: string;
}

export default function DobaseSidebar({ recordId }: DobaseSidebarProps) {
  const [threads, setThreads] = useState<DobaseThread[]>([]);
  const [docs, setDocs] = useState<DobaseDocument[]>([]);
  const [files, setFiles] = useState<DobaseFile[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const base = process.env.DOBASE_URL;
    const token = process.env.DOBASE_TOKEN;
    if (!base || !token) {
      setError('Dobase API not configured');
      setLoading(false);
      return;
    }

    const opts = { headers: { Authorization: `Bearer ${token}` } };

    Promise.all([
      fetch(`${base}/api/v1/contacts/${recordId}/chat_threads`, opts).then((r) => r.json()),
      fetch(`${base}/api/v1/contacts/${recordId}/documents`, opts).then((r) => r.json()),
      fetch(`${base}/api/v1/contacts/${recordId}/files`, opts).then((r) => r.json()),
    ])
      .then(([t, d, f]) => {
        setThreads(t);
        setDocs(d);
        setFiles(f);
      })
      .catch(() => setError('Failed to load Dobase data'))
      .finally(() => setLoading(false));
  }, [recordId]);

  if (loading) return <div style={styles.container}>Loading Dobase context…</div>;
  if (error) return <div style={styles.container}>{error}</div>;

  return (
    <div style={styles.container}>
      <h4 style={styles.heading}>Recent chats</h4>
      {threads.length === 0 ? (
        <p style={styles.empty}>No chat threads</p>
      ) : (
        threads.map((t) => (
          <a key={t.id} href={t.deepLink} target="_blank" rel="noopener noreferrer" style={styles.link}>
            {t.lastMessage}
          </a>
        ))
      )}

      <h4 style={styles.heading}>Docs</h4>
      {docs.length === 0 ? (
        <p style={styles.empty}>No documents</p>
      ) : (
        docs.map((d) => (
          <a key={d.id} href={d.deepLink} target="_blank" rel="noopener noreferrer" style={styles.link}>
            {d.title}
          </a>
        ))
      )}

      <h4 style={styles.heading}>Files</h4>
      {files.length === 0 ? (
        <p style={styles.empty}>No files</p>
      ) : (
        files.map((f) => (
          <a key={f.id} href={f.deepLink} target="_blank" rel="noopener noreferrer" style={styles.link}>
            {f.filename}
          </a>
        ))
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    fontFamily: 'var(--font-sans)',
    fontSize: 'var(--font-size-sm)',
    padding: '12px',
  },
  heading: {
    margin: '12px 0 4px',
    fontWeight: 'var(--font-weight-medium)',
  },
  link: {
    display: 'block',
    padding: '4px 0',
    color: 'var(--brand-primary)',
    textDecoration: 'none',
  },
  empty: {
    color: 'var(--surface-border)',
    fontStyle: 'italic',
    margin: '4px 0',
  },
};
