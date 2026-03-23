(function () {
  const TARGET_CHAIN_ID = 11155111n;
  const TARGET_CHAIN_HEX = "0xaa36a7";
  const CHAINS = {
    11155111: "Sepolia"
  };

  const state = {
    provider: null,
    signer: null,
    contract: null,
    account: null,
    samples: []
  };

  const ethersLib = window.ethers;
  const connectBtn = document.getElementById("connectBtn");
  const ERC20_ABI = [
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 value) returns (bool)"
  ];
  const PERMIT2_ABI = [
    "function allowance(address user, address token, address spender) view returns (uint160 amount, uint48 expiration, uint48 nonce)",
    "function approve(address token, address spender, uint160 amount, uint48 expiration) external"
  ];

  function hasEthers() {
    return !!(ethersLib && ethersLib.BrowserProvider && ethersLib.Contract);
  }

  function hasEthereumProvider() {
    return typeof window.ethereum !== "undefined";
  }

  function setConnectButtonState() {
    if (!connectBtn) return;

    if (!hasEthers()) {
      connectBtn.textContent = "Web3 Library Missing";
      connectBtn.disabled = true;
      return;
    }

    if (!hasEthereumProvider()) {
      connectBtn.textContent = "Install MetaMask";
      connectBtn.disabled = false;
      return;
    }

    connectBtn.textContent = state.account ? shortenAddress(state.account) : "Connect Wallet";
    connectBtn.disabled = false;
  }

  function getConfig() {
    if (window.ALM_CONFIG) return window.ALM_CONFIG;
    if (typeof contractAddress !== "undefined" && typeof contractABI !== "undefined") {
      return { contractAddress, contractABI };
    }
    throw new Error("Missing ALM frontend configuration.");
  }

  function shortenAddress(address) {
    if (!address) return "-";
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  }

  function setText(id, value) {
    const node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function setStatus(message, isError = false) {
    const node = document.getElementById("statusMessage");
    if (!node) return;
    node.textContent = message;
    node.classList.toggle("err", isError);
    node.classList.toggle("ok", !isError);
  }

  function extractErrorData(err) {
    return (
      err?.data ||
      err?.info?.error?.data ||
      err?.error?.data ||
      err?.receipt?.revertReason ||
      null
    );
  }

  function parseContractError(err) {
    try {
      const data = extractErrorData(err);
      if (!data || !hasEthers()) return null;
      const cfg = getConfig();
      const iface = new ethersLib.Interface(cfg.contractABI);
      const decoded = iface.parseError(data);
      if (!decoded) return null;
      const args = (decoded.args || []).map((v) => String(v)).join(", ");
      return args ? `${decoded.name}(${args})` : decoded.name;
    } catch {
      return null;
    }
  }

  function explainError(err) {
    const decoded = parseContractError(err);
    if (decoded) return decoded;
    return err?.shortMessage || err?.reason || err?.message || "Unknown error";
  }

  function hasRequiredFunctions() {
    try {
      const cfg = getConfig();
      const iface = new ethersLib.Interface(cfg.contractABI);
      const required = [
        "deposit",
        "withdraw",
        "executeEngineCycleWithLiquidity",
        "syncVolatilityIndex",
        "performUpkeep"
      ];
      return required.every((name) => {
        try {
          iface.getFunction(name);
          return true;
        } catch {
          return false;
        }
      });
    } catch {
      return false;
    }
  }

  function formatUnitsSafe(value, decimals = 18, digits = 4) {
    try {
      const num = Number(ethersLib.formatUnits(value, decimals));
      return Number.isFinite(num) ? num.toLocaleString(undefined, { maximumFractionDigits: digits }) : "-";
    } catch {
      return "-";
    }
  }

  async function safeCall(fn, fallback = null) {
    try {
      return await fn();
    } catch {
      return fallback;
    }
  }

  async function fetchEthUsdFallback() {
    const response = await fetch("https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd", {
      method: "GET"
    });
    if (!response.ok) throw new Error("Price API unavailable.");
    const payload = await response.json();
    const usd = payload?.ethereum?.usd;
    if (typeof usd !== "number" || !Number.isFinite(usd) || usd <= 0) {
      throw new Error("Invalid market price payload.");
    }
    return usd;
  }

  function explainReadiness(ready) {
    if (!ready) return "Engine readiness unavailable";
    const missing = [];
    if (!ready[1]) missing.push("PoolInteractor not set");
    if (!ready[2]) missing.push("PositionTracker not set");
    if (!ready[3]) missing.push("Rebalance liquidity is zero");
    if (!ready[4]) missing.push("Vault is not pool volatility updater");
    if (missing.length === 0) return "Engine ready";
    return `Engine not ready: ${missing.join(", ")}`;
  }

  function parseAmount(value, decimals = 18) {
    if (!value || Number(value) <= 0) return 0n;
    return ethersLib.parseUnits(String(value), decimals);
  }

  async function initProvider() {
    if (!hasEthers()) throw new Error("ethers.js failed to load.");
    if (!hasEthereumProvider()) throw new Error("MetaMask not found.");
    state.provider = new ethersLib.BrowserProvider(window.ethereum);
    return state.provider;
  }

  async function ensureSepolia() {
    if (!hasEthereumProvider()) throw new Error("MetaMask not found.");

    const network = await state.provider.getNetwork();
    if (network.chainId === TARGET_CHAIN_ID) return;

    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: TARGET_CHAIN_HEX }]
      });
    } catch (switchErr) {
      if (switchErr?.code === 4902) {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: TARGET_CHAIN_HEX,
            chainName: "Sepolia",
            rpcUrls: ["https://ethereum-sepolia-rpc.publicnode.com"],
            nativeCurrency: { name: "Sepolia ETH", symbol: "SEP", decimals: 18 },
            blockExplorerUrls: ["https://sepolia.etherscan.io"]
          }]
        });
      } else {
        throw switchErr;
      }
    }
  }

  async function ensureContractDeployed() {
    const cfg = getConfig();
    const code = await state.provider.getCode(cfg.contractAddress);
    if (!code || code === "0x") {
      throw new Error(`No contract code found at ${cfg.contractAddress} on current network.`);
    }
  }

  async function ensureContract(withSigner = false) {
    const cfg = getConfig();
    if (!state.provider) await initProvider();

    if (withSigner) {
      state.signer = await state.provider.getSigner();
      state.contract = new ethersLib.Contract(cfg.contractAddress, cfg.contractABI, state.signer);
    } else {
      state.contract = new ethersLib.Contract(cfg.contractAddress, cfg.contractABI, state.provider);
    }
    return state.contract;
  }

  async function connectWallet() {
    try {
      if (!hasEthers()) {
        alert("Web3 library failed to load. Refresh the page and try again.");
        return;
      }

      if (!hasEthereumProvider()) {
        const hint = window.location.protocol === "file:"
          ? "MetaMask often blocks file:// pages. Open this app via a local server (http://localhost)."
          : "MetaMask extension is required to connect your wallet.";
        alert(hint);
        return;
      }

      setConnectButtonState();
      if (connectBtn) connectBtn.textContent = "Connecting...";

      await initProvider();
      await window.ethereum.request({ method: "eth_requestAccounts" });
      await ensureSepolia();
      const signer = await state.provider.getSigner();
      state.account = await signer.getAddress();
      setText("walletAddress", state.account);
      setConnectButtonState();

      const network = await state.provider.getNetwork();
      setText("networkName", CHAINS[Number(network.chainId)] || `Chain ${network.chainId}`);

      const cfg = getConfig();
      setText("contractAddressDisplay", cfg.contractAddress);

      await ensureContract(false);
      await ensureContractDeployed();
      await refreshAll();
    } catch (err) {
      setConnectButtonState();
      const msg = err?.shortMessage || err?.message || "Wallet connection failed.";
      alert(msg);
      setStatus(msg, true);
    }
  }

  async function callAndWait(label, fn) {
    try {
      setStatus(`${label} pending...`);
      const tx = await fn();
      setStatus(`${label}: submitted ${tx.hash.slice(0, 10)}...`);
      const receipt = await tx.wait();

      if (label === "Withdraw") {
        let shown = false;
        try {
          const cfg = getConfig();
          const iface = new ethersLib.Interface(cfg.contractABI);
          for (const log of receipt.logs || []) {
            try {
              const parsed = iface.parseLog(log);
              if (parsed?.name === "Withdrawal") {
                const ethReturned = formatUnitsSafe(parsed.args.ethReturned, 18, 8);
                const usdcReturned = formatUnitsSafe(parsed.args.usdcReturned, 6, 4);
                setStatus(`Withdraw confirmed: ${ethReturned} ETH + ${usdcReturned} USDC returned`);
                shown = true;
                break;
              }
            } catch {
            }
          }
        } catch {
        }

        if (!shown) {
          setStatus(`${label}: confirmed`);
        }
      } else {
        setStatus(`${label}: confirmed`);
      }

      await refreshAll();
    } catch (err) {
      setStatus(`${label} failed: ${explainError(err)}`, true);
    }
  }

  async function runVaultAction(label, action) {
    try {
      if (!state.account) {
        await connectWallet();
        if (!state.account) {
          throw new Error("Wallet connection is required to continue.");
        }
      }
      if (!state.provider) {
        throw new Error("Web3 provider is not initialized.");
      }
      await ensureSepolia();
      const network = await state.provider.getNetwork();
      setText("networkName", CHAINS[Number(network.chainId)] || `Chain ${network.chainId}`);

      await ensureContract(true);
      await ensureContractDeployed();

      if (!hasRequiredFunctions()) {
        throw new Error("ABI mismatch: required write functions are missing.");
      }

      await action();
    } catch (err) {
      const message = `${label} failed: ${explainError(err)}`;
      setStatus(message, true);
      alert(message);
    }
  }

  async function assertIntegrationConfigured() {
    const contract = await ensureContract(false);
    const status = await contract.getIntegrationStatus();
    if (!status?.[0]) {
      throw new Error("Pool interactor is not configured in contract state.");
    }
  }

  async function ensurePermit2UsdcAllowance(usdcAmount) {
    if (usdcAmount <= 0n) return;

    const signer = state.signer || (await state.provider.getSigner());
    const owner = state.account || (await signer.getAddress());
    const vaultAddress = getConfig().contractAddress;
    const usdcAddress = await state.contract.USDC();
    const permit2Address = await state.contract.permit2();

    if (!usdcAddress || usdcAddress === ethersLib.ZeroAddress) {
      throw new Error("USDC token address is not configured in vault.");
    }
    if (!permit2Address || permit2Address === ethersLib.ZeroAddress) {
      throw new Error("Permit2 address is not configured in vault.");
    }

    const usdc = new ethersLib.Contract(usdcAddress, ERC20_ABI, signer);
    const permit2 = new ethersLib.Contract(permit2Address, PERMIT2_ABI, signer);

    const erc20Allowance = await usdc.allowance(owner, permit2Address);
    if (erc20Allowance < usdcAmount) {
      setStatus("Step 1/3: Approving USDC to Permit2...");
      const approveTx = await usdc.approve(permit2Address, ethersLib.MaxUint256);
      setStatus(`USDC approve submitted ${approveTx.hash.slice(0, 10)}...`);
      await approveTx.wait();
    }

    const allowanceInfo = await permit2.allowance(owner, usdcAddress, vaultAddress);
    const permit2Amount = allowanceInfo?.[0] ?? 0n;
    const permit2Expiry = Number(allowanceInfo?.[1] ?? 0);
    const now = Math.floor(Date.now() / 1000);
    const hasValidExpiry = permit2Expiry > now + 120;

    if (permit2Amount < usdcAmount || !hasValidExpiry) {
      const maxUint160 = (1n << 160n) - 1n;
      const expiry = now + 60 * 60 * 24 * 30;
      setStatus("Step 2/3: Approving Permit2 allowance to vault...");
      const permit2Tx = await permit2.approve(usdcAddress, vaultAddress, maxUint160, expiry);
      setStatus(`Permit2 approve submitted ${permit2Tx.hash.slice(0, 10)}...`);
      await permit2Tx.wait();
    }
  }

  async function refreshHome() {
    const contract = await ensureContract(false);
    const notes = [];
    let hasErrorNote = false;
    const totalShares = await safeCall(() => contract.totalShares(), 0n);
    const paused = await safeCall(() => contract.paused(), false);
    const auto = await safeCall(() => contract.autoRebalanceEnabled(), false);
    const price = await safeCall(() => contract.getEthUsdcPrice(), null);
    const ready = await safeCall(() => contract.getEngineReadiness(), null);
    const volSnap = await safeCall(() => contract.getVolatilitySnapshot(), null);

    setText("kpiTotalShares", formatUnitsSafe(totalShares ?? 0n, 18));
    setText("kpiPaused", paused ? "Yes" : "No");
    setText("kpiAutoRebalance", auto ? "Enabled" : "Disabled");

    if (price == null) {
      setText("kpiPrice", "-");
    } else if (price === 0n) {
      const fallbackPrice = await safeCall(fetchEthUsdFallback, null);
      if (fallbackPrice == null) {
        setText("kpiPrice", "0 (on-chain)");
        notes.push("On-chain ETH/USDC price returned 0 and fallback API failed.");
        hasErrorNote = true;
      } else {
        setText("kpiPrice", `${fallbackPrice.toLocaleString(undefined, { maximumFractionDigits: 2 })} (fallback)`);
        notes.push("On-chain ETH/USDC price is 0; showing fallback market price.");
      }
    } else {
      setText("kpiPrice", formatUnitsSafe(price, 18));
    }

    setText("kpiReady", ready?.[0] ? "Ready" : "Not Ready");
    setText("kpiVolatility", volSnap?.[0]?.toString?.() || "-");

    if (ready?.[0]) {
      notes.push("Engine ready.");
    } else {
      notes.push(explainReadiness(ready));
    }

    if (notes.length > 0) {
      setStatus(notes.join(" "), hasErrorNote);
    }
  }

  async function refreshVault() {
    const contract = await ensureContract(false);
    const idleEth = await safeCall(() => contract.idleEth(), 0n);
    const idleUsdc = await safeCall(() => contract.idleUsdc(), 0n);
    const totalEth = await safeCall(() => contract.totalEthDeposited(), 0n);
    const totalUsdc = await safeCall(() => contract.totalUsdcDeposited(), 0n);
    const totalShares = await safeCall(() => contract.totalShares(), 0n);
    const volIdx = await safeCall(() => contract.getVolatilityIndex(), 0n);
    const volValue = await safeCall(() => contract.getVolatilityValue(), 0n);
    const activePos = await safeCall(() => contract.activePositionCount(), 0n);
    const interval = await safeCall(() => contract.interval(), 0n);

    setText("idleEth", formatUnitsSafe(idleEth ?? 0n, 18));
    setText("idleUsdc", formatUnitsSafe(idleUsdc ?? 0n, 6));
    setText("totalEthDeposited", formatUnitsSafe(totalEth ?? 0n, 18));
    setText("totalUsdcDeposited", formatUnitsSafe(totalUsdc ?? 0n, 6));
    setText("volatilityIndex", (volIdx ?? 0n).toString());
    setText("volatilityValue", formatUnitsSafe(volValue ?? 0n, 0));
    setText("activePositionCount", (activePos ?? 0n).toString());
    setText("interval", (interval ?? 0n).toString());

    let userSharesRaw = 0n;
    if (state.account) {
      const idxPlusOne = await safeCall(() => contract.userIndex(state.account), 0n);
      if (idxPlusOne > 0n) {
        const user = await safeCall(() => contract.users(idxPlusOne - 1n), null);
        userSharesRaw = user?.sharesOwned ?? 0n;
      }
    }

    const ownershipBps = totalShares > 0n ? (userSharesRaw * 10000n) / totalShares : 0n;
    const ownershipPct = Number(ownershipBps) / 100;
    setText("userShares", formatUnitsSafe(userSharesRaw, 18, 6));
    setText("userOwnership", `${ownershipPct.toFixed(2)}%`);
  }

  function drawVolatilityChart() {
    const canvas = document.getElementById("volatilityCanvas");
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const width = canvas.width;
    const height = canvas.height;

    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = "rgba(8,15,30,0.9)";
    ctx.fillRect(0, 0, width, height);

    const points = state.samples.length ? state.samples : [0.2, 0.4, 0.3, 0.6, 0.5];
    const max = Math.max(...points, 1);

    ctx.strokeStyle = "rgba(255,255,255,0.1)";
    for (let i = 1; i < 5; i++) {
      const y = (height / 5) * i;
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
      ctx.stroke();
    }

    const grad = ctx.createLinearGradient(0, 0, width, 0);
    grad.addColorStop(0, "#59c3ff");
    grad.addColorStop(1, "#9c6bff");
    ctx.strokeStyle = grad;
    ctx.lineWidth = 3;

    ctx.beginPath();
    points.forEach((value, i) => {
      const x = (i / Math.max(points.length - 1, 1)) * (width - 40) + 20;
      const y = height - (value / max) * (height - 40) - 20;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  }

  async function refreshInsights() {
    const contract = await ensureContract(false);
    const [volSnap, rebalancePreview, integration] = await Promise.all([
      contract.getVolatilitySnapshot(),
      contract.previewShouldRebalanceNow(),
      contract.getIntegrationStatus()
    ]);

    const volIndex = Number(volSnap?.[0] || 0);
    const volValue = Number(volSnap?.[1] || 0);

    setText("insightVolIndex", String(volIndex));
    setText("insightVolValue", Number.isFinite(volValue) ? volValue.toLocaleString() : "-");
    setText("insightRebalance", rebalancePreview?.[0] ? "Yes" : "No");

    setText("sigPoolInteractor", integration?.[0] ? "Yes" : "No");
    setText("sigVolPush", integration?.[1] ? "Yes" : "No");
    setText("sigCanRebalance", integration?.[2] ? "Yes" : "No");
    setText("sigDrift", integration?.[4] ? "Yes" : "No");

    const normalized = Math.max(0.05, Math.min(1, volIndex / 3 + (volValue % 1000000) / 1000000));
    state.samples.push(normalized);
    if (state.samples.length > 40) state.samples.shift();
    drawVolatilityChart();
  }

  async function refreshAll() {
    try {
      const page = document.body.dataset.page;
      if (page === "home") await refreshHome();
      if (page === "vault") await refreshVault();
      if (page === "insights") await refreshInsights();
    } catch (err) {
      setStatus(`Read failed: ${err.shortMessage || err.message}`, true);
    }
  }

  function bindVaultActions() {
    const depositBtn = document.getElementById("depositBtn");
    const withdrawBtn = document.getElementById("withdrawBtn");
    const executeCycleBtn = document.getElementById("executeCycleBtn");
    const syncVolBtn = document.getElementById("syncVolBtn");
    const performUpkeepBtn = document.getElementById("performUpkeepBtn");
    const refreshBtn = document.getElementById("refreshBtn");

    depositBtn?.addEventListener("click", async () => {
      const initialLabel = depositBtn.textContent;
      depositBtn.disabled = true;
      depositBtn.textContent = "Processing...";

      try {
        await runVaultAction("Deposit", async () => {
          setStatus("Deposit validation in progress...");
          const ethInput = document.getElementById("depositEth").value;
          const usdcInput = document.getElementById("depositUsdc").value;
          const ethValue = parseAmount(ethInput, 18);
          const usdcAmount = parseAmount(usdcInput, 6);

          if (ethValue <= 0n && usdcAmount <= 0n) {
            throw new Error("Enter ETH and/or USDC amount before deposit.");
          }

          const minDepositUsdc = 20n * 1000000n;
          const ethPrice = await safeCall(() => state.contract.getEthUsdcPrice(), 0n);
          const depositValueUsdc = usdcAmount + ((ethValue * ethPrice) / (10n ** 18n));

          if (depositValueUsdc < minDepositUsdc) {
            throw new Error("Minimum deposit is 20 USDC equivalent. Increase ETH amount.");
          }

          if (usdcAmount > 0n) {
            await ensurePermit2UsdcAllowance(usdcAmount);
          }

          setStatus("Step 3/3: Submitting deposit transaction...");
          await callAndWait("Deposit", () => state.contract.deposit(usdcAmount, { value: ethValue }));
        });
      } finally {
        depositBtn.disabled = false;
        depositBtn.textContent = initialLabel;
      }
    });

    withdrawBtn?.addEventListener("click", async () => {
      await runVaultAction("Withdraw", async () => {
        const shares = document.getElementById("withdrawShares").value;
        const sharesToBurn = parseAmount(shares, 18);

        if (sharesToBurn <= 0n) {
          throw new Error("Enter shares to burn before withdraw.");
        }

        await callAndWait("Withdraw", () => state.contract.withdraw(sharesToBurn));
      });
    });

    executeCycleBtn?.addEventListener("click", async () => {
      await runVaultAction("Engine Cycle", async () => {
        await assertIntegrationConfigured();
        const liq = document.getElementById("rebalanceLiquidity").value;
        const liquidity = parseAmount(liq, 0);

        if (liquidity <= 0n) {
          throw new Error("Enter rebalance liquidity amount.");
        }

        await callAndWait("Engine Cycle", () => state.contract.executeEngineCycleWithLiquidity(liquidity));
      });
    });

    syncVolBtn?.addEventListener("click", async () => {
      await runVaultAction("Sync Volatility", async () => {
        await assertIntegrationConfigured();
        await callAndWait("Sync Volatility", () => state.contract.syncVolatilityIndex());
      });
    });

    performUpkeepBtn?.addEventListener("click", async () => {
      await runVaultAction("Perform Upkeep", async () => {
        await assertIntegrationConfigured();
        const upkeep = await state.contract.checkUpkeep("0x");
        if (!upkeep?.[0]) {
          throw new Error("Upkeep not needed yet. Wait for interval/drift condition.");
        }
        await callAndWait("Perform Upkeep", () => state.contract.performUpkeep("0x"));
      });
    });

    refreshBtn?.addEventListener("click", refreshAll);
  }

  function bindInsightsActions() {
    const refreshBtn = document.getElementById("refreshInsightsBtn");
    refreshBtn?.addEventListener("click", refreshAll);
    setInterval(() => {
      if (document.body.dataset.page === "insights") refreshInsights();
    }, 12000);
  }

  function setupTilt() {
    document.querySelectorAll(".tilt").forEach((card) => {
      card.addEventListener("mousemove", (e) => {
        const rect = card.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;
        const rotateY = ((x / rect.width) - 0.5) * 10;
        const rotateX = ((y / rect.height) - 0.5) * -10;
        card.style.transform = `perspective(900px) rotateX(${rotateX}deg) rotateY(${rotateY}deg)`;
      });
      card.addEventListener("mouseleave", () => {
        card.style.transform = "perspective(900px) rotateX(0) rotateY(0)";
      });
    });
  }

  function setActiveNav() {
    const page = document.body.dataset.page;
    document.querySelectorAll("[data-nav]").forEach((link) => {
      if (link.dataset.nav === page) link.classList.add("active");
    });
  }

  async function boot() {
    if (!hasRequiredFunctions()) {
      setStatus("Configuration ABI is missing required vault functions.", true);
    }

    setConnectButtonState();
    setActiveNav();
    setupTilt();
    bindVaultActions();
    bindInsightsActions();

    const cfg = getConfig();
    setText("contractAddressDisplay", cfg.contractAddress);

    if (connectBtn) connectBtn.addEventListener("click", connectWallet);

    if (window.ethereum) {
      window.ethereum.on("accountsChanged", () => window.location.reload());
      window.ethereum.on("chainChanged", () => window.location.reload());
    }

    if (hasEthereumProvider() && hasEthers()) {
      try {
        await initProvider();
        const accounts = await window.ethereum.request({ method: "eth_accounts" });
        if (accounts?.length) {
          state.account = accounts[0];
          setText("walletAddress", state.account);
          setConnectButtonState();
          const network = await state.provider.getNetwork();
          setText("networkName", CHAINS[Number(network.chainId)] || `Chain ${network.chainId}`);
        }
      } catch {
      }
    }

    try {
      await ensureContract(false);
      await refreshAll();
    } catch (err) {
      const message = err?.shortMessage || err?.message || "Connect wallet to start.";
      setStatus(message);
    }
  }

  boot();
})();
